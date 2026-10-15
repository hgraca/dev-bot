IMAGE := ruby:3.3
RUN := docker run --rm -it -v "$(CURDIR)":/srv -v umbrella-docs-bundle:/usr/local/bundle -w /srv -p 4000:4000 -p 35729:35729 $(IMAGE)

.PHONY: serve preview build data

serve:
	$(RUN) sh -c "bundle install && bundle exec jekyll serve --host 0.0.0.0 --livereload"

preview:
	$(RUN) sh -c "bundle install && bundle exec jekyll serve --host 0.0.0.0 --livereload --unpublished"

build:
	docker run --rm -v "$(CURDIR)":/srv -v umbrella-docs-bundle:/usr/local/bundle -w /srv $(IMAGE) sh -c "bundle install && JEKYLL_ENV=production bundle exec jekyll build"

data:
	node ../scripts/generate-projects.mjs
