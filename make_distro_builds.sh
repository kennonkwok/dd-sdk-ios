#!/bin/zsh

if [ ! -f "Cartfile" ]; then
	echo "\`make_distro_builds.sh\` must be run from the same place with `Cartfile`"; exit 1
fi

# hide dependency-manager-tests from carthage, 
# DO NOT FORGET TO REVERT BACK IN TRAP BELOW!
mv dependency-manager-tests/ .dependency-manager-tests/

# create temporary xcconfig for carthage build
set -euo pipefail
xcconfig=$(mktemp /tmp/static.xcconfig.XXXXXX)
trap 'rm -f "$xcconfig" ; mv .dependency-manager-tests/ dependency-manager-tests/ ;' INT TERM HUP EXIT
echo "BUILD_LIBRARY_FOR_DISTRIBUTION = YES" >> $xcconfig
export XCODE_XCCONFIG_FILE="$xcconfig"

# clear existing carthage artifacts
rm -rf Carthage/
rm Cartfile.resolved

# fetch 3rd party deps via carthage
echo "carthage bootstrap with no build..."
carthage bootstrap --no-build

echo "carthage build without skipping current"
carthage build --platform iOS --use-xcframeworks --no-skip-current
