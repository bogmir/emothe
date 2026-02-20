defmodule Emothe.Repo.Migrations.AddAuthorityField do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :authority, :string
    end
  end
end
