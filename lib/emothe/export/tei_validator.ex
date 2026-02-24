defmodule Emothe.Export.TeiValidator do
  @moduledoc """
  Validates TEI-XML against the TEI P5 RelaxNG schema using xmllint.
  """

  @doc """
  Validates an XML string against the bundled TEI RelaxNG schema.

  Returns:
  - `{:ok, :valid}` — XML conforms to the TEI P5 schema
  - `{:error, :xmllint_not_found}` — xmllint is not installed
  - `{:error, :schema_not_found}` — schema file missing from priv/schemas/
  - `{:error, errors}` — validation failed; `errors` is a list of error strings
  """
  @spec validate(String.t()) :: {:ok, :valid} | {:error, atom()} | {:error, [String.t()]}
  def validate(xml) when is_binary(xml) do
    with :ok <- check_xmllint(),
         :ok <- check_schema() do
      run_validation(xml)
    end
  end

  defp schema_path do
    Application.app_dir(:emothe, "priv/schemas/tei_all.rng")
  end

  defp check_xmllint do
    case System.find_executable("xmllint") do
      nil -> {:error, :xmllint_not_found}
      _path -> :ok
    end
  end

  defp check_schema do
    if File.exists?(schema_path()) do
      :ok
    else
      {:error, :schema_not_found}
    end
  end

  defp run_validation(xml) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "tei-validate-#{System.unique_integer([:positive])}.xml"
      )

    try do
      File.write!(tmp_path, xml)

      {output, exit_code} =
        System.cmd("xmllint", ["--noout", "--relaxng", schema_path(), tmp_path],
          stderr_to_stdout: true
        )

      case exit_code do
        0 ->
          {:ok, :valid}

        _ ->
          errors =
            output
            |> String.split("\n")
            |> Enum.reject(&(&1 == ""))
            |> Enum.reject(&String.ends_with?(&1, "validates"))
            |> Enum.reject(&String.ends_with?(&1, "fails to validate"))
            |> Enum.map(&String.replace(&1, tmp_path, "TEI-XML"))

          {:error, errors}
      end
    after
      File.rm(tmp_path)
    end
  end
end
