#!/bin/bash

set -eu -o pipefail
# Disable hashing because we're tweaking /usr/bin/ruby
set +h

echo "Installing Stile extras..."
# We need ruby for our build scripts - and it has to be a modern version.
sudo yum -y install ruby23
sudo update-alternatives --set ruby /usr/bin/ruby2.3
# This should now use gem from ruby2.3
sudo gem install bundler

# We need to install the stile-build gem which has our rakefile helpers.
STILE_BUILD_VERSION=2.0.4
aws s3 cp s3://stile-ci-assets/stile_build/stile_build-$STILE_BUILD_VERSION.gem /tmp/stile_build-$STILE_BUILD_VERSION.gem
# This should automatically pull dependant gems.
sudo gem install /tmp/stile_build-$STILE_BUILD_VERSION.gem
rm -f /tmp/stile_build-$STILE_BUILD_VERSION.gem
