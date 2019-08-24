defmodule Mony do
  @moduledoc """
  A script to extract data from bank statements in PDF format from Zions Bank in Utah.
  """
  import NimbleParsec
  NimbleCSV.define(CSVParser, separator: ",", escape: "\"")

  credit_title =
    string(" ")
    |> repeat()
    |> integer(min: 1)
    |> string(" ")
    |> repeat()
    |> string("DEPOSITS/CREDITS")

  debit_title =
    ignore(string(" ") |> repeat())
    |> ignore(integer(min: 1))
    |> ignore(string(" "))
    |> string("CHARGES/DEBITS")

  header =
    ignore(string(" ") |> repeat())
    |> string("Date")
    |> ignore(string(" ") |> repeat())
    |> string("Amount")
    |> ignore(string(" ") |> repeat())
    |> string("Description")

  date =
    ascii_string([?0..?9], 2)
    |> string("/")
    |> ascii_string([?0..?9], 2)
    |> reduce({Enum, :join, []})

  amount =
    times(integer(max: 3) |> ignore(string(",")), max: 1)
    |> ascii_string([?0..?9], max: 3)
    |> string(".")
    |> ascii_string([?0..?9], 2)
    |> reduce({Enum, :join, []})

  # same as ascii_string([?\s..?~])
  description =
    ascii_string([32..43, 45..126], min: 1)
    |> reduce({Enum, :join, []})

  bank_event =
    ignore(string(" ") |> repeat())
    |> concat(date)
    |> ignore(string(" ") |> repeat())
    |> concat(amount)
    |> ignore(string(" ") |> repeat())
    |> concat(description)

  defparsec(:credit_title, credit_title)
  defparsec(:debit_title, debit_title)
  defparsec(:header, header)
  defparsec(:bank_event, bank_event)

  def main([file_name]) do
    file_name
    |> convert_to_text()
    |> parse_statement()
    |> output_as_csv()
  end

  defp convert_to_text(file_name) do
    {pdf_content, 0} = System.cmd("pdftotext", ["-layout", file_name, "-"])

    pdf_content
  end

  # 7 states of parsing the pdf document are ordered as:
  # 1. :searching_for_credit_title
  # 2. :searching_for_credit_heading
  # 3. :scanning_credits
  # 4. :searching_for_debit_title
  # 5. :searching_for_debit_heading
  # 6. :scanning_debits
  # 7. :ok
  # The states in which data is added to the state are 3 and 6
  defp parse_statement(pdf_content) do
    pdf_content
    |> String.split("\n")
    |> Enum.reduce_while(
      {:searching_for_credit_title, %{credits: [], debits: []}},
      &parse_credits_and_debits/2
    )
  end

  def output_as_csv({:ok, result}) do
    {:ok, io_credits} = File.open("credits.csv", [:write])
    {:ok, io_debits} = File.open("debits.csv", [:write])

    IO.binwrite(
      io_credits,
      CSVParser.dump_to_iodata([~w[Date Amount Description] | result.credits])
    )

    IO.binwrite(
      io_debits,
      CSVParser.dump_to_iodata([~w[Date Amount Description] | result.debits])
    )
  end

  defp parse_credits_and_debits(str, {:searching_for_credit_title, state}) do
    case credit_title(str) do
      {:ok, _match, _, _, _, _} -> {:cont, {:searching_for_credit_heading, state}}
      {:error, _, _, _, _, _} -> {:cont, {:searching_for_credit_title, state}}
    end
  end

  defp parse_credits_and_debits(str, {:searching_for_credit_heading, state}) do
    case header(str) do
      {:ok, _match, _, _, _, _} -> {:cont, {:scanning_credits, state}}
      {:error, _, _, _, _, _} -> {:cont, {:searching_for_credit_heading, state}}
    end
  end

  defp parse_credits_and_debits(
         str,
         {:scanning_credits, state = %{credits: credits}}
       ) do
    case bank_event(str) do
      {:ok, event, _, _, _, _} ->
        {:cont, {:scanning_credits, %{state | credits: [event | credits]}}}

      {:error, _, _, _, _, _} ->
        {:cont, {:searching_for_debit_title, state}}
    end
  end

  defp parse_credits_and_debits(str, {:searching_for_debit_title, state}) do
    case debit_title(str) do
      {:ok, _, _, _, _, _} ->
        {:cont, {:searching_for_debit_heading, state}}

      {:error, _, _, _, _, _} ->
        {:cont, {:searching_for_debit_title, state}}
    end
  end

  defp parse_credits_and_debits(str, {:searching_for_debit_heading, state}) do
    case header(str) do
      {:ok, _, _, _, _, _} -> {:cont, {:scanning_debits, state}}
      {:error, _, _, _, _, _} -> {:cont, {:searching_for_debit_heading, state}}
    end
  end

  defp parse_credits_and_debits(
         str,
         {:scanning_debits, state = %{credits: credits, debits: debits}}
       ) do
    case bank_event(str) do
      {:ok, event, _, _, _, _} ->
        {:cont, {:scanning_debits, %{credits: credits, debits: [event | debits]}}}

      {:error, _, _, _, _, _} ->
        {:halt, {:ok, state}}
    end
  end
end
