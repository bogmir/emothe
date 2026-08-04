defmodule Emothe.Repo.Migrations.CreatePlaces do
  use Ecto.Migration

  def change do
    create table(:places, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :type, :string, null: false
      add :parent_place_id, references(:places, type: :binary_id, on_delete: :restrict)
      add :latitude, :float
      add :longitude, :float
      add :is_fictional, :boolean, default: false, null: false
      add :authority, :string
      add :authority_id, :string
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:places, [:slug])
    create index(:places, [:parent_place_id])

    create unique_index(:places, [:authority, :authority_id], where: "authority_id IS NOT NULL")

    create table(:place_names, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :place_id, references(:places, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :language, :string
      add :is_preferred, :boolean, default: false, null: false
      add :is_historical, :boolean, default: false, null: false
      add :position, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:place_names, [:place_id])

    create unique_index(:place_names, ["place_id", "coalesce(language, '')"],
             where: "is_preferred",
             name: :one_preferred_name_per_place_and_language
           )

    create table(:play_places, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false

      add :place_id, references(:places, type: :binary_id, on_delete: :restrict), null: false

      add :role, :string, default: "setting", null: false
      add :position, :integer, default: 0
      add :note, :text
      add :origin, :string, default: "manual", null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:play_places, [:play_id, :place_id])
    create index(:play_places, [:place_id])
  end
end
