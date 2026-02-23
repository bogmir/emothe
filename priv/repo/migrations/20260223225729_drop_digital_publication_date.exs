defmodule Emothe.Repo.Migrations.DropDigitalPublicationDate do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      remove :digital_publication_date, :date
    end
  end
end
