RSpec.describe ZeroDowntimeMigrations::Validation::AddColumn do
  let(:error) { ZeroDowntimeMigrations::UnsafeMigrationError }

  context "with a default" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          add_column :users, :active, :boolean, default: true
        end
      end
    end

    it "raises an unsafe migration error" do
      expect { migration.migrate(:up) }.to raise_error(error)
    end
  end

  context "with a false default" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          add_column :users, :active, :boolean, default: false
        end
      end
    end

    it "raises an unsafe migration error" do
      expect { migration.migrate(:up) }.to raise_error(error)
    end
  end

  context "with a null default" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          add_column :users, :active, :boolean, default: nil
        end
      end
    end

    it "does not raise an unsafe migration error" do
      expect { migration.migrate(:up) }.not_to raise_error(error)
    end
  end

  context "without a default" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          add_column :users, :active, :boolean
        end
      end
    end

    it "does not raise an unsafe migration error" do
      expect { migration.migrate(:up) }.not_to raise_error(error)
    end
  end

  context "with a not nullable declaration" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          add_column :users, :active, :boolean, null: false
        end
      end
    end

    it "raises an unsafe migration error" do
      expect { migration.migrate(:up) }.to raise_error(error)
    end
  end

  context "with a nullable declaration" do
    let(:migration) do
      Class.new(ActiveRecord::Migration[5.0]) do
        def change
          add_column :users, :active, :boolean, null: true
        end
      end
    end

    it "raises an unsafe migration error" do
      expect { migration.migrate(:up) }.not_to raise_error(error)
    end
  end
end
