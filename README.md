## Dev

Setup
```sh
bundle install
bundle exec tapioca init
# bundle exec tapioca dsl
# bundle exec srb rbi suggest-typed
```

Linting
```sh
bundle exec srb typecheck
bundle exec rubocop -c .rubocop.yml --autocorrect
```

### Tests

```
bundle exec rake test
```

## Run

```
ruby update.rb

# Or partial update
ruby update.rb demo
```

Define env var `NO_DATA` to process and output only metadata.

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

## Dev

Setup
```
bundle install
bundle exec tapioca init
bundle exec tapioca dsl
bundle exec srb rbi suggest-typed

echo "# typed: false
sig { returns(T.untyped) }
def logger; end

class Hash
  sig { returns(Hash) }
  def compact_blank; end
end

class Array
  sig { returns(Array) }
  def compact_blank; end
end

class Time
  sig { returns(Time) }
  def self.current; end
end
" > sorbet/rbi/kernel.rbi
```

Tests and Validation
```
bundle exec rubocop --parallel -c .rubocop.yml --autocorrect
bundle exec srb typecheck
bundle exec rake test
```
