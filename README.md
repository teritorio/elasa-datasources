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

# Or partial update
ruby update.rb demo
```

## Docker

```
docker-compose build
docker-compose run --rm datasources ruby update.rb
docker-compose run --rm datasources ruby update.rb demo
```

Run NGINX http server
```
docker-compose up -d nginx
```
