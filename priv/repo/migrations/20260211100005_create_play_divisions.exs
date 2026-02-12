defmodule Emothe.Repo.Migrations.CreatePlayDivisions do
  use Ecto.Migration

  def change do
    create table(:play_divisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :parent_id, references(:play_divisions, type: :binary_id, on_delete: :delete_all)
      add :type, :string, null: false
      add :number, :integer
      add :title, :string
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:play_divisions, [:play_id])
    create index(:play_divisions, [:parent_id])
  end
end
