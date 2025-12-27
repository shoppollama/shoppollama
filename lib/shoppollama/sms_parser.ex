defmodule Shoppollama.SmsParser do
  @moduledoc """
  Parses natural language messages to extract SMS information
  """

  def sms_request?(message) do
    message = String.downcase(message)

    sms_keywords = ["send", "text", "sms", "message"]
    phone_pattern = ~r/\b\d{10,15}\b/

    has_sms_keyword = Enum.any?(sms_keywords, &String.contains?(message, &1))
    has_phone_number = Regex.match?(phone_pattern, message)

    has_sms_keyword and has_phone_number
  end

  def parse_sms_message(message) do
    # Extract phone number
    phone_number = extract_phone_number(message)
    
    # Extract the message content
    sms_content = extract_message_content(message)

    %{
      phone_number: phone_number,
      message: sms_content
    }
  end

  defp extract_phone_number(message) do
    case Regex.run(~r/\b(\d{10,15})\b/, message) do
      [_, phone] -> phone
      nil -> nil
    end
  end

  defp extract_message_content(message) do
    # Look for message content in quotes or after "with the message"
    cond do
      # Look for content in single quotes
      match = Regex.run(~r/with the message ['"]([^'"]+)['"]/, message) ->
        [_, content] = match
        content

      # Look for content in double quotes anywhere
      match = Regex.run(~r/['"]([^'"]+)['"]/, message) ->
        [_, content] = match
        content

      # Look for "message X" pattern
      match = Regex.run(~r/message (.+)$/, message) ->
        [_, content] = match
        String.trim(content)

      # Default message
      true ->
        "Hello from ShoppOllama!"
    end
  end
end