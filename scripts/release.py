#!/usr/bin/env python3
"""Prepare a verified Sparkle update, then optionally upload a GitHub Release draft."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.build/viewin/SourcePackages/artifacts/sparkle/Sparkle/bin'
ACCOUNT = 'app.viewin.updates'
NS = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}


def run(*args, capture=False):
    result = subprocess.run([str(a) for a in args], check=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None, text=True)
    return result.stdout.strip() if capture else None


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_appcast(path, *, version, build, archive, download_url):
    item = ET.parse(path).find('./channel/item')
    require(item is not None, 'The generated appcast has no update item.')
    enclosure = item.find('enclosure')
    require(enclosure is not None, 'The update item has no archive.')
    require(item.findtext('sparkle:version', namespaces=NS) == build or
            enclosure.get('{%s}version' % NS['sparkle']) == build, 'Appcast build number does not match the app.')
    require(item.findtext('sparkle:shortVersionString', namespaces=NS) == version or
            enclosure.get('{%s}shortVersionString' % NS['sparkle']) == version, 'Appcast version does not match the app.')
    require(enclosure.get('url') == download_url, 'Unexpected update download URL.')
    require(enclosure.get('length') == str(archive.stat().st_size), 'Update archive length does not match.')
    signature = enclosure.get('{%s}edSignature' % NS['sparkle'], '')
    require(len(base64.b64decode(signature, validate=True)) == 64, 'Missing or invalid EdDSA signature.')


def prepare(args):
    app = args.app.resolve()
    require(app.is_dir() and app.suffix == '.app', 'Choose an exported Viewin.app directory.')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == 'com.felikslv.Viewin', 'Only the release Viewin app can be distributed.')
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    require(re.fullmatch(r'\d+\.\d+\.\d+', version), 'Use a stable x.y.z marketing version.')
    require(re.fullmatch(r'\d+(?:\.\d+)*', build), 'Use a numeric, increasing build number.')
    match = re.fullmatch(r'https://github\.com/([\w.-]+/[\w.-]+)/releases/latest/download/appcast\.xml', info.get('SUFeedURL', ''))
    require(match is not None, 'The app must point to its public GitHub Release appcast.')
    repo = match.group(1)
    tools = args.sparkle_tools.resolve()
    public_key = run(tools / 'generate_keys', '--account', ACCOUNT, '-p', capture=True)
    require(info.get('SUPublicEDKey') == public_key, 'The app verification key does not match the local signing key.')
    require(len(base64.b64decode(public_key, validate=True)) == 32, 'Invalid public update key.')
    # Export from Xcode with Developer ID before packaging. Do not re-sign with --deep.
    details = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True, check=True).stderr
    require('Authority=Developer ID Application:' in details, 'Export with a Developer ID Application certificate first.')
    run('codesign', '--verify', '--deep', '--strict', app)
    run('xcrun', 'stapler', 'validate', app)
    require((app / 'Contents/Helpers/viewin').is_file(), 'The app is missing its bundled CLI.')
    require(args.notes.is_file() and args.notes.stat().st_size > 0, 'Provide a nonempty Markdown release notes file.')
    output = args.output.resolve()
    require(not output.exists(), 'Choose a new output directory; existing files are never overwritten.')
    output.mkdir(parents=True)
    archive = output / ('Viewin-%s.zip' % version)
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    notes = archive.with_suffix('.md')
    shutil.copyfile(args.notes, notes)
    tag = 'v' + version
    prefix = 'https://github.com/%s/releases/download/%s/' % (repo, tag)
    run(tools / 'generate_appcast', '--account', ACCOUNT, '--download-url-prefix', prefix,
        '--embed-release-notes', '--maximum-deltas', '0', output)
    appcast = output / 'appcast.xml'
    validate_appcast(appcast, version=version, build=build, archive=archive, download_url=prefix + archive.name)
    # Metadata enables the separate draft command to verify the exact prepared files.
    metadata = dict(repository=repo, tag=tag, version=version, build=build, archive=archive.name,
                    archiveSHA256=digest(archive), appcastSHA256=digest(appcast), notes=notes.name)
    (output / 'release.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print('Prepared %s in %s. No files have been uploaded.' % (tag, output))


def draft(args):
    output = args.directory.resolve()
    metadata = json.loads((output / 'release.json').read_text())
    repo, tag = metadata['repository'], metadata['tag']
    require(re.fullmatch(r'[\w.-]+/[\w.-]+', repo) is not None and re.fullmatch(r'v\d+\.\d+\.\d+', tag), 'Invalid release metadata.')
    require(Path(metadata['archive']).name == metadata['archive'] and Path(metadata['notes']).name == metadata['notes'], 'Invalid release file paths.')
    archive, appcast, notes = output / metadata['archive'], output / 'appcast.xml', output / metadata['notes']
    require(digest(archive) == metadata['archiveSHA256'] and digest(appcast) == metadata['appcastSHA256'], 'Prepared files changed. Prepare the release again.')
    validate_appcast(appcast, version=metadata['version'], build=metadata['build'], archive=archive,
                     download_url='https://github.com/%s/releases/download/%s/%s' % (repo, tag, archive.name))
    # Require an existing remote tag. This does not push source or create a tag from an arbitrary default branch.
    run('gh', 'api', 'repos/%s/git/ref/tags/%s' % (repo, tag), capture=True)
    run('gh', 'release', 'create', tag, '--repo', repo, '--verify-tag', '--draft',
        '--title', 'Viewin ' + metadata['version'], '--notes-file', notes, archive, appcast)
    print('Draft created. Review it on GitHub before publishing.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prep = commands.add_parser('prepare', help='Create a signed update from an exported, notarized app; never uploads.')
    prep.add_argument('app', type=Path)
    prep.add_argument('--notes', type=Path, required=True)
    prep.add_argument('--output', type=Path, required=True)
    prep.add_argument('--sparkle-tools', type=Path, default=TOOLS)
    upload = commands.add_parser('draft', help='Upload prepared files to a draft Release for an existing remote tag.')
    upload.add_argument('directory', type=Path)
    args = parser.parse_args()
    try:
        (prepare if args.command == 'prepare' else draft)(args)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, ET.ParseError) as error:
        parser.exit(1, 'Release preparation failed: %s\n' % error)


if __name__ == '__main__':
    main()
