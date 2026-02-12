defmodule Emothe.Repo.Migrations.CreatePlayElements do
  use Ecto.Migration

  def change do
    create table(:play_elements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :division_id, references(:play_divisions, type: :binary_id, on_delete: :delete_all)
      add :parent_id, references(:play_elements, type: :binary_id, on_delete: :delete_all)
      add :character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)
      add :type, :string, null: false
      add :content, :text
      add :speaker_label, :string
      add :line_number, :integer
      add :line_id, :string
      add :verse_type, :string
      add :part, :string
      add :is_aside, :boolean, default: false
      add :rend, :string
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:play_elements, [:play_id])
    create index(:play_elements, [:division_id])
    create index(:play_elements, [:parent_id])
    create index(:play_elements, [:character_id])
    create index(:play_elements, [:type])
  end
end
