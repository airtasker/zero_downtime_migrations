# ![LendingHome](https://avatars0.githubusercontent.com/u/5448482?s=24&v=4) zero_downtime_migrations
[![Code Climate](https://codeclimate.com/github/LendingHome/zero_downtime_migrations/badges/gpa.svg)](https://codeclimate.com/github/LendingHome/zero_downtime_migrations) [![Coverage](https://codeclimate.com/github/LendingHome/zero_downtime_migrations/badges/coverage.svg)](https://codeclimate.com/github/LendingHome/zero_downtime_migrations) [![Gem Version](https://badge.fury.io/rb/zero_downtime_migrations.svg)](http://badge.fury.io/rb/zero_downtime_migrations)

> Zero downtime migrations with ActiveRecord 3+ and PostgreSQL.

Catch problematic migrations at development/test time! Heavily inspired by these similar projects:

* https://github.com/ankane/strong_migrations
* https://github.com/foobarfighter/safe-migrations

## Installation

Simply add this gem to the project `Gemfile`.

```ruby
gem "zero_downtime_migrations"
```

## Usage

This gem will automatically **raise exceptions when potential database locking migrations are detected**.

It checks for common things like:

* Adding a column with a default
* Adding a non-concurrent index
* Mixing data changes with index or schema migrations
* Performing data or schema migrations with the DDL transaction disabled
* Using `each` instead of `find_each` to loop thru `ActiveRecord` objects

These exceptions display clear instructions of how to perform the same operation the "zero downtime way".

## Validations

### Adding a column with a default

#### Bad

This can take a long time with significant database size or traffic and lock your table!

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  def change
    add_column :posts, :published, :boolean, default: true
  end
end
```

#### Good

First let’s add the column without a default. When we add a column with a default it has to lock the table while it performs an UPDATE for ALL rows to set this new default.

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  def change
    add_column :posts, :published, :boolean
  end
end
```

Then we’ll set the new column default in a separate migration. Note that this does not update any existing data! This only sets the default for newly inserted rows going forward.

```ruby
class SetPublishedDefaultOnPosts < ActiveRecord::Migration
  def change
    change_column_default :posts, :published, from: nil, to: true
  end
end
```

Finally we’ll backport the default value for existing data in batches. This should be done in its own migration as well. Updating in batches allows us to lock 1000 rows at a time (or whatever batch size we prefer).

```ruby
class BackportPublishedDefaultOnPosts < ActiveRecord::Migration
  def up
    say_with_time "Backport posts.published default" do
      Post.unscoped.select(:id).find_in_batches.with_index do |batch, index|
        say("Processing batch #{index}\r", true)
        Post.unscoped.where(id: batch).update_all(published: true)
      end
    end
  end
end
```

### Adding an index concurrently

#### Bad

This action can lock your database table while indexing existing data!

```ruby
class IndexUsersOnEmail < ActiveRecord::Migration
  def change
    add_index :users, :email
  end
end
```

#### Good

Instead, let's add the index concurrently in its own migration with the DDL transaction disabled.

This allows PostgreSQL to build the index without locking in a way that prevent concurrent inserts, updates, or deletes on the table. Standard indexes lock out writes (but not reads) on the table.

```ruby
class IndexUsersOnEmail < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_index :users, :email, algorithm: :concurrently
  end
end
```

### Mixing data/index/schema migrations

#### Bad

Performing migrations that change the schema, update data, or add indexes within one big transaction is unsafe!

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  def change
    add_column :posts, :published, :boolean
    Post.unscoped.update_all(published: true)
    add_index :posts, :published
  end
end
```

#### Good

Instead, let's split apart these types of migrations into separate files.

* Introduce schema changes with methods like `create_table` or `add_column` in one file. These should be run within a DDL transaction so that they can be rolled back if there are any issues.
* Update data with methods like `update_all` or `save` in another file. Data migrations tend to be much more error prone than changing the schema or adding indexes.
* Add indexes concurrently within their own file as well. Indexes should be created without the DDL transaction enabled to avoid table locking.

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  def change
    add_column :posts, :published, :boolean
  end
end
```

```ruby
class BackportPublishedOnPosts < ActiveRecord::Migration
  def up
    Post.unscoped.update_all(published: true)
  end
end
```

```ruby
class IndexPublishedOnPosts < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_index :posts, :published, algorithm: :concurrently
  end
end
```

### Disabling the DDL transaction

#### Bad

The DDL transaction should only be disabled for migrations that add indexes. All other types of migrations should keep the DDL transaction enabled so that changes can be rolled back if any unexpected errors occur.

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_column :posts, :published, :boolean
  end
end
```

```ruby
class UpdatePublishedOnPosts < ActiveRecord::Migration
  disable_ddl_transaction!

  def up
    Post.unscoped.update_all(published: true)
  end
end
```

#### Good

Any other data or schema changes must live in their own migration files with the DDL transaction enabled just in case they make changes that need to be rolled back.

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  def change
    add_column :posts, :published, :boolean
  end
end
```

```ruby
class UpdatePublishedOnPosts < ActiveRecord::Migration
  def up
    Post.unscoped.update_all(published: true)
  end
end
```

### Looping thru `ActiveRecord::Base` objects

#### Bad

This might accidentally load tens or hundreds of thousands of records into memory all at the same time!

```ruby
class BackportPublishedDefaultOnPosts < ActiveRecord::Migration
  def up
    Post.unscoped.each do |post|
      post.update_attribute(published: true)
    end
  end
end
```

#### Good

Let's use the `find_each` method to fetch records in batches instead.

```ruby
class BackportPublishedDefaultOnPosts < ActiveRecord::Migration
  def up
    Post.unscoped.find_each do |post|
      post.update_attribute(published: true)
    end
  end
end
```

### Renaming a column

#### Bad
```ruby
class AddPublishedToPosts < ActiveRecord::Migration[5.0]
  def change
    rename_column :posts, :published, :published_new_name
  end
end
```

#### Good
* Introduce schema changes with methods like `create_table` or `add_column`
* Copy data with methods like `update_all`
* Introduce code to write to both columns
* Deploy
* Add code to stop writing to original column
* Deploy
* Drop the column in last separate deploy

```ruby
class AddPublishedToPosts < ActiveRecord::Migration[5.0]
  def change
    add_column :posts, :published_DEPRECATED, :boolean  #published is original column
    Post.update_all("\"published_DEPRECATED\"=published") #need to quote capitals in postgres
  end
end
```

```ruby
class CopyPublishedDataOnPosts < ActiveRecord::Migration[5.0]
  def change
    remove_column :posts, :published
  end
end
```

### Removing a column

#### Bad
```ruby
class RemovePublishedFromPosts < ActiveRecord::Migration[5.0]
  def change
    remove_column :posts, :published
  end
end
```

#### Good
* Introduce code to ignore column
* Deploy
* Drop the column in last separate deploy

```ruby
class User < ActiveRecord::Base
 ignore_columns :column_to_remove
end
```

```ruby
class RemoveColumnFromUsers < ActiveRecord::Migration[5.0]
  def change
    remove_column :users, :column_to_remove
  end
end
```

### Dropping a table

If old code is still using the models associated with this table before cutover, it can cause outages and confusion during deployment.

#### Bad
```ruby
class DropPostsTable < ActiveRecord::Migration[5.0]
  def change
    drop_table :posts
  end
end
```

#### Good

Make sure all old code is removed first and then add the migration in a seperate PR after the first change is released.

*First PR*

```
  rm app/models/Post.rb
  # migrate any dependant code
```

*After first PR is deployed*

```ruby
class DropPostsTable < ActiveRecord::Migration[5.0]
  def change
    safety_assured { drop_table :posts }
  end
end
```

### Adding a not nullable column

When we add a column with the not nullable option it has to
lock the table while it performs an UPDATE for ALL rows to
set a default.

#### Bad
```ruby
class AddColumnWithNotNullContraint < ActiveRecord::Migration[5.0]
  def change
    add_column :posts, :region_id, :integer, null: false, default: 1
  end
end
```

Adding a not nullable column is onerous, but if it's really
really necessary there are two pathways depending on the size
of the table:

#### Good

*Small tables (< 500 000 rows)*

First let’s add the column without a default.

```ruby
class AddRegionToPosts < ActiveRecord::Migration[5.0]
  def change
    add_column :posts, :region_id, :integer
  end
end
```

Then we’ll set the new column default in a separate migration.
Note that this does not update any existing data. This only
sets the default for newly inserted rows going forward.

```ruby
class AddDefaultRegionIdToPosts < ActiveRecord::Migration[5.0]
  def change
    change_column_default :posts, :region_id, 1
  end
end
```

Then we’ll backport the default value for existing data in
batches. This should be done in its own migration as well.
Updating in batches allows us to lock 1000 rows at a time
(or whatever batch size we prefer).

```ruby
class BackportDefaultRegionIdInPosts < ActiveRecord::Migration[5.0]
  def change
    Post.select(:id).find_in_batches.with_index do |records, index|
      Rails.logger.info "Processing batch \#{index + 1} for region_id in posts"
      Post.where(id: records).update_all(region_id: 1)
    end
  end
end
```

Finally add the not null constraint on the table - note this
still requires a full table scan to check all values

```ruby
class ChangeRegionIdToNotNullable < ActiveRecord::Migration
  def change
    change_column_null :posts, :region_id, false
  end
end
```

*Larger tables (> 500 000 rows)*

Firstly, create a new table with the addition of the non-nullable
column and adjust the code to write to both tables but still reading
from the original.

```ruby
class AddNewPostsWithNotNullableRegionId < ActiveRecord::Migration
  def change
    create_table :posts_new do |t|
      t.integer, region_id, default: 1, null: false
      # ....
    end
  end
end
```

Then backport the expected value for existing data in batches.
This should be done in its own migration.

Finally, in a seperate PR switch the code to use the new table
and follow it up with yet another PR to drop the old table.

If you're 100% positive that this migration is already safe, then
wrap the call to `add_column` in a `safety_assured` block.

```ruby
class AddRegiondIdToPosts < ActiveRecord::Migration
  def change
    safety_assured { add_column :posts, :region_id, :integer, null: false, default: 1 }
  end
end
```

### TODO

* Changing a column type
* Renaming a table

## Disabling "zero downtime migration" enforcements

We can disable any of these "zero downtime migration" enforcements by wrapping them in a `safety_assured` block.

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  def change
    safety_assured do
      add_column :posts, :published, :boolean, default: true
    end
  end
end
```

We can also mark an entire migration as safe by using the `safety_assured` helper method.

```ruby
class AddPublishedToPosts < ActiveRecord::Migration
  safety_assured

  def change
    add_column :posts, :published, :boolean
    Post.unscoped.where("created_at >= ?", 1.day.ago).update_all(published: true)
  end
end
```

Enforcements can be globally disabled by setting `ENV["SAFETY_ASSURED"]` when running migrations.

```bash
SAFETY_ASSURED=1 bundle exec rake db:migrate --trace
```

These enforcements are **automatically disabled by default for the following scenarios**:

* The database schema is being loaded with `rake db:schema:load` instead of `db:migrate`
* The current migration is a reverse (down) migration
* The current migration is named `RollupMigrations`

## Testing

```bash
bundle exec rspec
```

## Contributing

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so we don't break it in a future version unintentionally.
* Commit, do not mess with the version or history.
* Open a pull request. Bonus points for topic branches.

## Authors

* [Sean Huber](https://github.com/shuber)

## License

[MIT](https://github.com/lendinghome/zero_downtime_migrations/blob/master/LICENSE) - Copyright © 2016 LendingHome
