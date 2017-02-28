#!/bin/bash

set -eu -o pipefail
# Disable hashing because we're tweaking /usr/bin/ruby
set +h

echo "Installing Stile extras..."

yum install -y \
    gcc gcc-c++ make autoconf automake libtool bison patch \
    kernel-headers zlib-devel libffi-devel readline-devel openssl-devel;

# We need ruby for our build scripts - and it has to be a modern version.
# Also, the packaging in amazon linux is a bit, well, fucked.
mkdir -p /tmp/rbbuild
mkdir -p /tmp/jemallocbuild

echo '/usr/local/lib64' > /etc/ld.so.conf.d/local.conf
ldconfig

pushd /tmp/jemallocbuild

wget -O jemalloc-4.4.0.tar.bz2 https://github.com/jemalloc/jemalloc/releases/download/4.4.0/jemalloc-4.4.0.tar.bz2
tar -x --strip-components 1 -f jemalloc-4.4.0.tar.bz2
./configure --prefix=/usr/local --libdir=/usr/local/lib64 --enable-prof --enable-stats
make -j 2
make install
ldconfig

popd

pushd /tmp/rbbuild

export RUBY_CFLAGS="-O3 -fno-fast-math -ggdb3 -Wall -Wextra -Wno-unused-parameter -Wno-parentheses -Wno-long-long \
    -Wno-missing-field-initializers -Wunused-variable -Wpointer-arith -Wwrite-strings -Wdeclaration-after-statement \
    -Wimplicit-function-declaration -Wdeprecated-declarations -Wno-packed-bitfield-compat"

wget -O ruby-2.3.3.tar.gz https://cache.ruby-lang.org/pub/ruby/2.3/ruby-2.3.3.tar.gz
tar -x --strip-components 1 -f ruby-2.3.3.tar.gz
CFLAGS="$RUBY_CFLAGS" ./configure --prefix=/usr/local --disable-install-rdoc --with-jemalloc --libdir=/usr/local/lib64
CFLAGS="$RUBY_CFLAGS" make -j 2
make install

# Make sure we get rid of system ruby.
update-alternatives --install /usr/bin/ruby ruby /usr/local/bin/ruby 30 \
    --slave /usr/bin/erb erb /usr/local/bin/erb \
    --slave /usr/bin/gem gem /usr/local/bin/gem \
    --slave /usr/bin/irb irb /usr/local/bin/irb \
    --slave /usr/bin/rake rake /usr/local/bin/rake \
    --slave /usr/bin/rdoc rdoc /usr/local/bin/rdoc \
    --slave /usr/bin/ri ri /usr/local/bin/ri \
    --slave /usr/bin/testrb testrb /dev/null \
    --slave /usr/lib64/pkgconfig/ruby.pc ruby.pc /usr/local/lib64/pkgconfig/ruby-2.3.pc \
    --slave /usr/share/man/man1/erb.1.gz erb.1 /usr/local/share/man/man1/erb.1 \
    --slave /usr/share/man/man1/irb.1.gz irb.1 /usr/local/share/man/man1/irb.1 \
    --slave /usr/share/man/man1/rake.1.gz rake.1 /dev/null \
    --slave /usr/share/man/man1/ri.1.gz ri.1 /usr/local/share/man/man1/ri.1 \
    --slave /usr/share/man/man1/ruby.1.gz ruby.1 /usr/local/share/man/man1/ruby.1
update-alternatives --set ruby /usr/local/bin/ruby

/usr/local/bin/gem install bundler
/usr/local/bin/gem install activesupport -v '~> 5'
/usr/local/bin/gem install httparty -v '~> 0.14'
/usr/local/bin/gem install addressable -v '~> 2'


popd

# Copy the termination monitor somewhere
cp /tmp/conf/bin/spot_termination_monitor.rb /usr/local/bin
chmod +x /usr/local/bin/spot_termination_monitor.rb
