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
