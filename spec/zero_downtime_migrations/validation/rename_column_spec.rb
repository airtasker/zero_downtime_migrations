RSpec.describe ZeroDowntimeMigrations::Validation::RenameColumn do
  let(:error) { ZeroDowntimeMigrations::UnsafeMigrationError }

  context "when rename_column is called without safety_assured block" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          rename_column :users, :fname, :first_name
        end
      end
    end

    it "raises an unsafe migration error" do
      expect { migration.migrate(:up) }.to raise_error(error)
    end
  end
end
