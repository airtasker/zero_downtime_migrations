module ZeroDowntimeMigrations
  class Validation
    class AddColumn < Validation
      def validate!
        error!(not_null_message) if options[:null] == false
        error!(default_present_message) if options.key?(:default) && !options[:default].nil? # only nil is safe
      end

      private

      def default_present_message
        <<-MESSAGE.strip_heredoc
          Adding a column with a default is unsafe!

          This can take a long time with significant database
          size or traffic and lock your table!

          First let’s add the column without a default. When we add
          a column with a default it has to lock the table while it
          performs an UPDATE for ALL rows to set this new default.

            class Add#{column_title}To#{table_title} < ActiveRecord::Migration
              def change
                add_column :#{table}, :#{column}, :#{column_type}
              end
            end

          Then we’ll set the new column default in a separate migration.
          Note that this does not update any existing data! This only
          sets the default for newly inserted rows going forward.

            class AddDefault#{column_title}To#{table_title} < ActiveRecord::Migration
              def change
                change_column_default :#{table}, :#{column}, from: nil, to: #{column_default}
              end
            end

          Finally we’ll backport the default value for existing data in
          batches. This should be done in its own migration as well.
          Updating in batches allows us to lock 1000 rows at a time
          (or whatever batch size we prefer).

            class BackportDefault#{column_title}To#{table_title} < ActiveRecord::Migration
              def up
                say_with_time "Backport #{table_model}.#{column} default" do
                  #{table_model}.unscoped.select(:id).find_in_batches.with_index do |records, index|
                    say("Processing batch \#{index + 1}\\r", true)
                    #{table_model}.unscoped.where(id: records).update_all(#{column}: #{column_default})
                  end
                end
              end
            end

          Note that in some cases it may not even be necessary to backport a default value.

            class #{table_model} < ActiveRecord::Base
              def #{column}
                self["#{column}"] ||= #{column_default}
              end
            end

          If you're 100% positive that this migration is already safe, then wrap the
          call to `add_column` in a `safety_assured` block.

            class Add#{column_title}To#{table_title} < ActiveRecord::Migration
              def change
                safety_assured { add_column :#{table}, :#{column}, :#{column_type}, default: #{column_default} }
              end
            end
        MESSAGE
      end

      def not_null_message
        <<-MESSAGE.strip_heredoc
          Adding a not nullable column is unsafe!

          This can take a long time with significant database
          size or traffic and lock your table!

          When we add a column with the not nullable option it has to
          lock the table while it performs an UPDATE for ALL rows to
          set a default.

          Adding a not nullable column is onerous, but if it's really
          really necessary there are two pathways depending on the size
          of the table:

          Small tables (< 500 000 rows)

          First let’s add the column without a default.

            class Add#{column_title}To#{table_title} < ActiveRecord::Migration
              def change
                add_column :#{table}, :#{column}, :#{column_type}
              end
            end

          Then we’ll set the new column default in a separate migration.
          Note that this does not update any existing data. This only
          sets the default for newly inserted rows going forward.

            class AddDefault#{column_title}To#{table_title} < ActiveRecord::Migration
              def change
                change_column_default :#{table}, :#{column}, #{column_default}
              end
            end

          Then we’ll backport the default value for existing data in
          batches. This should be done in its own migration as well.
          Updating in batches allows us to lock 1000 rows at a time
          (or whatever batch size we prefer).

            class BackportDefault#{column_title}To#{table_title} < ActiveRecord::Migration
              def change
                #{table_model}.select(:id).find_in_batches.with_index do |records, index|
                  Rails.logger.info "Processing batch \#{index + 1} for #{column_title} in #{table_title}"
                  #{table_model}.where(id: records).update_all(#{column}: #{column_default})
                end
              end
            end

          Finally add the not null constraint on the table - note this
          still requires a full table scan to check all values

            class Change#{column_title}ToNotNullable < ActiveRecord::Migration
              def change
                change_column_null :#{table}, :#{column}, false
              end
            end

          Larger tables (> 500 000 rows)

          Firstly, create a new table with the addition of the non-nullable
          column and adjust the code to write to both tables but still reading
          from the original.

            class AddNew#{table}WithNotNullable#{column_title} < ActiveRecord::Migration
              def change
                create_table :#{table}_new do |t|
                  t.#{column_type}, #{column_title}, default: #{column_default}, null: false
                  ....
                end
              end
            end

          Then backport the expected value for existing data in batches.
          This should be done in its own migration.

          Finally, in a seperate PR switch the code to use the new table
          and follow it up with yet another PR to drop the old table.

          If you're 100% positive that this migration is already safe, then
          wrap the call to `add_column` in a `safety_assured` block.

            class Add#{column_title}To#{table_title} < ActiveRecord::Migration
              def change
                safety_assured { add_column :#{table}, :#{column}, :#{column_type}, null: false, default: #{column_default} }
              end
            end

        MESSAGE
      end

      def column
        args[1]
      end

      def column_default
        options[:default].inspect
      end

      def column_title
        column.to_s.camelize
      end

      def column_type
        args[2]
      end

      def table
        args[0]
      end

      def table_model
        table_title.singularize
      end

      def table_title
        table.to_s.camelize
      end
    end
  end
end
