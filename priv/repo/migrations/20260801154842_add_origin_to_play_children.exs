defmodule Emothe.Repo.Migrations.AddOriginToPlayChildren do
  use Ecto.Migration

  @tables [:play_editors, :play_sources, :play_editorial_notes]

  def change do
    for table <- @tables do
      # "manual" is the safe default: a row wrongly marked manual survives an import that
      # should have replaced it (visible, fixable); one wrongly marked tei is deleted.
      alter table(table) do
        add :origin, :string, null: false, default: "manual"
      end

      create index(table, [:play_id, :origin])
    end

    # Everything in the database at this point came out of a TEI import: the admin CRUD
    # pages for these three tables all write to the activity log, and it holds no create
    # entries for play_source, play_editor or play_editorial_note.
    for table <- @tables do
      execute "UPDATE #{table} SET origin = 'tei'", ""
    end
  end
end
