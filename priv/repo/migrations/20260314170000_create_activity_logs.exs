defmodule Emothe.Repo.Migrations.CreateActivityLogs do
  use Ecto.Migration

  def change do
    create table(:activity_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :play_id, references(:plays, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :changes, :map, default: %{}
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:activity_logs, [:user_id])
    create index(:activity_logs, [:play_id])
    create index(:activity_logs, [:action])
    create index(:activity_logs, [:resource_type])
    create index(:activity_logs, [:inserted_at])
  end
end
