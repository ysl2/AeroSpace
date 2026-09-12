#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="-"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh --ignore-xcodeproj
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --generate-git-hash --ignore-xcodeproj

swift build -c release -Xswiftc -warnings-as-errors

rm -rf .release && mkdir .release

app_contents=".release/AeroSpace.app/Contents"
mkdir -p "$app_contents/MacOS" "$app_contents/Resources"
cp .build/release/AeroSpaceApp "$app_contents/MacOS/AeroSpace"
cp .build/release/aerospace .release
cp docs/config-examples/default-config.toml "$app_contents/Resources"

plist="$app_contents/Info.plist"
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert CFBundleExecutable -string AeroSpace "$plist"
/usr/bin/plutil -insert CFBundleIdentifier -string bobko.aerospace "$plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$plist"
/usr/bin/plutil -insert LSUIElement -bool YES "$plist"

/usr/bin/codesign --force --sign "$codesign_identity" .release/AeroSpace.app

git checkout .

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospace

################
### VALIDATE ###
################

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-contains-hash .release/AeroSpace.app/Contents/MacOS/AeroSpace
check-contains-hash .release/aerospace

codesign -v .release/AeroSpace.app
codesign -v .release/aerospace

############
### PACK ###
############

mkdir -p ".release/AeroSpace-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-v$build_version/bin" && cp -r aerospace "AeroSpace-v$build_version/bin"
    cp -r AeroSpace.app "AeroSpace-v$build_version"
    zip -r "AeroSpace-v$build_version.zip" "AeroSpace-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospace aerospace-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AeroSpace-v$build_version.zip" \
        --build-version "$build_version"
done
