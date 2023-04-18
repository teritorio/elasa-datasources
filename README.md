## Dev

Setup
```sh
bundle install
bundle exec tapioca init
# bundle exec tapioca dsl
# bundle exec srb rbi suggest-typed
```

Tests and Validation
```sh
bundle exec srb typecheck
bundle exec rubocop -c .rubocop.yml --autocorrect
# bundle exec rake test
```

## Run

```
ruby update.rb
```

## Docker

```
docker-compose build
docker-compose run --rm datasources ruby update.rb
```
