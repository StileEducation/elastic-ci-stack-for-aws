.PHONY: all clean build build-ami upload create-stack update-stack download-mappings toc check-env-agent-token check-env-access-token

BUILDKITE_STACK_BUCKET ?= buildkite-aws-stack
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
VERSION ?= $(shell git describe --tags --candidates=1)
STACK_NAME ?= buildkite
SHELL=/bin/bash -o pipefail
TEMPLATES=templates/description.yml \
  templates/buildkite-elastic.yml \
  templates/autoscale.yml \
  templates/vpc.yml \
  templates/metrics.yml

all: setup build

build: build/aws-stack.json

.DELETE_ON_ERROR:
build/aws-stack.json: $(TEMPLATES) templates/mappings.yml
	-mkdir -p build/
	bundle exec cfoo $^ > $@
	sed -i.bak "s/BUILDKITE_STACK_VERSION=dev/BUILDKITE_STACK_VERSION=$(VERSION)/" $@

setup:
	bundle check || ((which bundle || gem install bundler --no-ri --no-rdoc) && bundle install --path vendor/bundle)

clean:
	-rm -f build/*

templates/mappings.yml:
	$(error Either run `make build-ami` to build the ami, or `make download-mappings` to download the latest public mappings)

download-mappings:
	echo "Downloading templates/mappings.yml for branch $(BRANCH)"
	curl -Lf -o templates/mappings.yml https://s3.amazonaws.com/buildkite-aws-stack/$(BRANCH)/mappings.yml
	touch templates/mappings.yml

build-ami:
	cd packer/; packer build buildkite-ami.json | tee ../packer.output
	cp templates/mappings.yml.template templates/mappings.yml
	sed -i.bak "s/packer_image_id/$$(grep -Eo 'ap-southeast-2: (ami-.+)' packer.output | cut -d' ' -f2)/" templates/mappings.yml

upload: build/aws-stack.json
	aws s3 sync --acl public-read build s3://$(BUILDKITE_STACK_BUCKET)/

config.json:
	test -s config.json || $(error Please create a config.json file)


ifndef BUILDKITE_AGENT_TOKEN
check-env-agent-token: ; $(error BUILDKITE_AGENT_TOKEN is undefined)
else
check-env-agent-token:
endif
ifndef BUILDKITE_API_ACCESS_TOKEN
check-env-access-token: ; $(error BUILDKITE_API_ACCESS_TOKEN is undefined)
else
check-env-access-token:
endif


extra_tags.json:
	echo "{}" > extra_tags.json

create-stack: config.json build/aws-stack.json extra_tags.json check-env-agent-token check-env-access-token
	aws cloudformation create-stack \
	--output text \
	--stack-name $(STACK_NAME) \
	--disable-rollback \
	--template-body "file://$(PWD)/build/aws-stack.json" \
	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
	--parameters "$$(cat config.json | sed -e "s/BUILDKITE_AGENT_TOKEN/$(BUILDKITE_AGENT_TOKEN)/g" | sed -e "s/BUILDKITE_API_ACCESS_TOKEN/$(BUILDKITE_API_ACCESS_TOKEN)/g")" \
	--tags "$$(cat extra_tags.json)"

validate: build/aws-stack.json
	aws cloudformation validate-template \
	--output table \
	--template-body "file://$(PWD)/build/aws-stack.json"

update-stack: config.json templates/mappings.yml build/aws-stack.json check-env-agent-token check-env-access-token
	aws cloudformation update-stack \
	--output text \
	--stack-name $(STACK_NAME) \
	--template-body "file://$(PWD)/build/aws-stack.json" \
	--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
	--parameters "$$(cat config.json | sed -e "s/BUILDKITE_AGENT_TOKEN/$(BUILDKITE_AGENT_TOKEN)/g" | sed -e "s/BUILDKITE_API_ACCESS_TOKEN/$(BUILDKITE_API_ACCESS_TOKEN)/g")" \
	--tags "$$(cat extra_tags.json)"

toc:
	docker run -it --rm -v "$$(pwd):/app" node:slim bash -c "npm install -g markdown-toc && cd /app && markdown-toc -i Readme.md"
