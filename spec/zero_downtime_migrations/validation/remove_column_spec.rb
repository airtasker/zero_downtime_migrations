RSpec.describe ZeroDowntimeMigrations::Validation::RemoveColumn do
  let(:error) { ZeroDowntimeMigrations::UnsafeMigrationError }

  context "when remove_column is called without safety_assured block" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          remove_column :users, :active
        end
      end
    end

    it "raises an unsafe migration error" do
      expect { migration.migrate(:up) }.to raise_error(error)
    end
  end
end
