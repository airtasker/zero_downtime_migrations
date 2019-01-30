module ZeroDowntimeMigrations
  class Validation
    class RenameColumn < Validation
      def validate!
        error!(rename_column_warning_message)
      end

      private

      def rename_column_warning_message
        <<-MESSAGE.strip_heredoc
          Renaming a column while a deployed and running version of the app
          depends on that column is unsafe!

          This can cause a signifant number of possibly critical errors while
          the older version of the app is running and expecting the column to have
          the original name.

          Three separate releases are required.

          First, add a new column and make sure the app is writing to it. Ensure
          that the accessor reads from both columns, e.g.

            class Add#{new_column_title}To#{table_title} < ActiveRecord::Migration
              def change
                add_column :#{table}, :#{new_column}, <data type and other options here>
              end
            end

            class #{table_model} < ActiveRecord::Base
              def #{new_column}
                super || attributes["#{old_column}"]
              end
            end

          Then, populate the new column with data from the previous one. The
          second release includes updates to queries to refer to the new column
          name.

          Finally, in a third release, remove the old column.

            class Remove#{old_column_title}From#{table_title} < ActiveRecord::Migration
              def change
                safety_assured { remove_column :#{table}, :#{old_column} }
              end
            end

          If you're 100% positive that this migration is already safe, then wrap
          the call to `rename_column` in a `safety_assured` block.

            class Rename#{old_column_title}To#{new_column_title}On#{table_title} < ActiveRecord::Migration
              def change
                safety_assured { rename_column :#{table}, :#{old_column}, :#{new_column} }
              end
            end
        MESSAGE
      end

      def old_column
        args[1]
      end

      def new_column
        args[2]
      end

      def old_column_title
        old_column.to_s.camelize
      end

      def new_column_title
        new_column.to_s.camelize
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
