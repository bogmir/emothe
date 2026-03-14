defmodule Emothe.ActivityLog.Diff do
  @moduledoc """
  Extracts a JSON-safe diff from an Ecto changeset.
  """

  @excluded_fields ~w(inserted_at updated_at hashed_password)a

  @doc """
  Returns a map of `%{field => [old_value, new_value]}` from a changeset's changes.
  Excludes timestamps and sensitive fields.
  """
  def from_changeset(%Ecto.Changeset{changes: changes, data: data}) do
    changes
    |> Map.drop(@excluded_fields)
    |> Enum.into(%{}, fn {field, new_value} ->
      old_value = Map.get(data, field)
      {to_string(field), [sanitize(old_value), sanitize(new_value)]}
    end)
  end

  def from_changeset(_), do: %{}

  defp sanitize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp sanitize(%Date{} = d), do: Date.to_iso8601(d)
  defp sanitize(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp sanitize(value) when is_atom(value), do: to_string(value)
  defp sanitize(value), do: value
end
