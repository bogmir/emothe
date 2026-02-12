defmodule Emothe.Repo.Migrations.CreatePlays do
  use Ecto.Migration

  def change do
    create table(:plays, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :title_sort, :string
      add :code, :string, null: false
      add :language, :string, default: "es"
      add :author_name, :string
      add :author_sort, :string
      add :author_attribution, :string
      add :publication_date, :string
      add :digital_publication_date, :date
      add :verse_count, :integer
      add :is_verse, :boolean, default: true
      add :publisher, :string
      add :pub_place, :string
      add :availability_note, :text
      add :project_description, :text
      add :editorial_declaration, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plays, [:code])
    create index(:plays, [:title_sort])
    create index(:plays, [:author_sort])
  end
end
