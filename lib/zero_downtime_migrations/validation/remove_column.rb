module ZeroDowntimeMigrations
  class Validation
    class RemoveColumn < Validation
      def validate!
        error!(remove_column_warning_message)
      end

      private

      def remove_column_warning_message
        <<-MESSAGE.strip_heredoc
          Removing a column while a deployed and running version of the app
          depends on that column is unsafe!

          This can cause a signifant number of possibly critical errors while
          the older version of the app is running and expecting the column to be
          there.

          First, deploy a version of the app which ignores the column. Note that
          Rails 5.0 introduces an `ignored_columns` feature, however for previous
          version of Rails you can use the `ignorable` gem to tell rails to
          ignore one or more columns. However, be aware that any queries which
          execute a `select * from table` could potentially still cause errors on
          Rails 4 relating to cached prepared statements. To mitigate this issue the
          following patch should be applied:

          https://github.com/rails/rails/issues/12330#issuecomment-244930976

          Example of ignoring a column using `ignorable` gem:

            class #{table_model} < ActiveRecord::Base
              ignore_columns #{column}
            end

          Then, deploy a version of the app which includes a migration to drop
          the column and removes the code to ignore the column.

          If you're 100% positive that this migration is already safe, then wrap
          the call to `remove_column` in a `safety_assured` block.

            class Remove#{column_title}From#{table_title} < ActiveRecord::Migration
              def change
                safety_assured { remove_column :#{table}, :#{column} }
              end
            end

          Note: When removing an attribute from a model which is serialized in
          API responses, be sure to consider how clients will handle responses
          without the attribute.
        MESSAGE
      end

      def column
        args[1]
      end

      def column_title
        column.to_s.camelize
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
