defmodule Shoppollama.MessageStore do
  @moduledoc """
  In-memory storage for chat messages with thread-safe operations and lifecycle management.
  This is an interim solution until persistent storage is implemented.
  """

  use GenServer
  require Logger

  # Configuration
  @max_conversations 1000
  @max_messages_per_conversation 500
  @cleanup_interval :timer.hours(1)
  @conversation_ttl :timer.hours(24)
  @message_cleanup_batch_size 50

  # Client API

  @doc "Starts the message store GenServer"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Adds a message to a conversation"
  def add_message(conversation_id, message) do
    with :ok <- validate_conversation_id(conversation_id),
         :ok <- validate_message(message) do
      try do
        GenServer.call(__MODULE__, {:add_message, conversation_id, message}, 10_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout adding message to conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error adding message: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get conversation statistics including message count and last activity
  """
  def get_conversation_stats(conversation_id) do
    with :ok <- validate_conversation_id(conversation_id) do
      try do
        GenServer.call(__MODULE__, {:get_conversation_stats, conversation_id}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout getting stats for conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error getting conversation stats: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Manually trigger cleanup of old conversations
  """
  def cleanup_old_conversations do
    GenServer.cast(__MODULE__, :cleanup_old_conversations)
  end

  @doc """
  Get total number of active conversations
  """
  def get_conversation_count do
    try do
      GenServer.call(__MODULE__, :get_conversation_count, 5_000)
    catch
      :exit, {:timeout, _} ->
        Logger.error("MessageStore timeout getting conversation count")
        {:error, :timeout}
      :exit, reason ->
        Logger.error("MessageStore error getting conversation count: #{inspect(reason)}")
        {:error, :genserver_error}
    end
  end

  @doc """
  Get conversation context including recent messages and metadata
  """
  def get_conversation_context(conversation_id, opts \\[]) do
    limit = Keyword.get(opts, :limit, 10)
    with :ok <- validate_conversation_id(conversation_id),
         :ok <- validate_limit(limit) do
      try do
        GenServer.call(__MODULE__, {:get_conversation_context, conversation_id, limit}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout getting context for conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error getting conversation context: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search messages within a conversation by content
  """
  def search_messages(conversation_id, query) do
    with :ok <- validate_conversation_id(conversation_id),
         :ok <- validate_search_query(query) do
      try do
        GenServer.call(__MODULE__, {:search_messages, conversation_id, query}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout searching messages in conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error searching messages: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get messages by role (user, assistant, system)
  """
  def get_messages_by_role(conversation_id, role) do
    with :ok <- validate_conversation_id(conversation_id),
         :ok <- validate_role(role) do
      try do
        GenServer.call(__MODULE__, {:get_messages_by_role, conversation_id, role}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout getting messages by role for conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error getting messages by role: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update conversation metadata
  """
  def update_conversation_metadata(conversation_id, metadata) do
    with :ok <- validate_conversation_id(conversation_id),
         :ok <- validate_metadata(metadata) do
      try do
        GenServer.call(__MODULE__, {:update_conversation_metadata, conversation_id, metadata}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout updating metadata for conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error updating conversation metadata: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Gets all messages for a conversation"
  def get_messages(conversation_id) do
    with :ok <- validate_conversation_id(conversation_id) do
      try do
        GenServer.call(__MODULE__, {:get_messages, conversation_id}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout getting messages for conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error getting messages: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Gets the last N messages for a conversation"
  def get_recent_messages(conversation_id, limit \\ 50) do
    with :ok <- validate_conversation_id(conversation_id),
         :ok <- validate_limit(limit) do
      try do
        GenServer.call(__MODULE__, {:get_recent_messages, conversation_id, limit}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout getting recent messages for conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error getting recent messages: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Clears all messages for a conversation"
  def clear_conversation(conversation_id) do
    with :ok <- validate_conversation_id(conversation_id) do
      try do
        GenServer.call(__MODULE__, {:clear_conversation, conversation_id}, 5_000)
      catch
        :exit, {:timeout, _} ->
          Logger.error("MessageStore timeout clearing conversation #{conversation_id}")
          {:error, :timeout}
        :exit, reason ->
          Logger.error("MessageStore error clearing conversation: #{inspect(reason)}")
          {:error, :genserver_error}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Gets conversation statistics"
  def get_stats do
    try do
      GenServer.call(__MODULE__, :get_stats, 5_000)
    catch
      :exit, {:timeout, _} ->
        Logger.error("MessageStore timeout getting stats")
        {:error, :timeout}
      :exit, reason ->
        Logger.error("MessageStore error getting stats: #{inspect(reason)}")
        {:error, :genserver_error}
    end
  end

  @doc "Cleans up old conversations based on age or size limits"
  def cleanup_old_conversations do
    GenServer.cast(__MODULE__, :cleanup_old_conversations)
  end

  # Input Validation Functions

  defp validate_conversation_id(conversation_id) do
    cond do
      is_nil(conversation_id) ->
        {:error, :invalid_conversation_id}
      not is_binary(conversation_id) and not is_atom(conversation_id) ->
        {:error, :invalid_conversation_id}
      is_binary(conversation_id) and String.trim(conversation_id) == "" ->
        {:error, :empty_conversation_id}
      is_binary(conversation_id) and String.length(conversation_id) > 255 ->
        {:error, :conversation_id_too_long}
      true ->
        :ok
    end
  end

  defp validate_message(message) do
    cond do
      is_nil(message) ->
        {:error, :nil_message}
      not is_map(message) ->
        {:error, :invalid_message_format}
      not Map.has_key?(message, :content) ->
        {:error, :missing_content}
      not Map.has_key?(message, :role) ->
        {:error, :missing_role}
      not is_binary(message.content) ->
        {:error, :invalid_content_type}
      String.trim(message.content) == "" ->
        {:error, :empty_content}
      String.length(message.content) > 10_000 ->
        {:error, :content_too_long}
      message.role not in [:user, :assistant, :system, "user", "assistant", "system"] ->
        {:error, :invalid_role}
      true ->
        :ok
    end
  end

  defp validate_limit(limit) do
    cond do
      is_nil(limit) ->
        {:error, :nil_limit}
      not is_integer(limit) ->
        {:error, :invalid_limit_type}
      limit < 1 ->
        {:error, :limit_too_small}
      limit > 1000 ->
        {:error, :limit_too_large}
      true ->
        :ok
    end
  end

  defp validate_search_query(query) do
    cond do
      is_nil(query) ->
        {:error, :nil_query}
      not is_binary(query) ->
        {:error, :invalid_query_type}
      String.trim(query) == "" ->
        {:error, :empty_query}
      String.length(query) > 500 ->
        {:error, :query_too_long}
      true ->
        :ok
    end
  end

  defp validate_role(role) do
    cond do
      is_nil(role) ->
        {:error, :nil_role}
      role not in [:user, :assistant, :system, "user", "assistant", "system"] ->
        {:error, :invalid_role}
      true ->
        :ok
    end
  end

  defp validate_metadata(metadata) do
    cond do
      is_nil(metadata) ->
        {:error, :nil_metadata}
      not is_map(metadata) ->
        {:error, :invalid_metadata_type}
      map_size(metadata) > 50 ->
        {:error, :metadata_too_large}
      true ->
        :ok
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)
    {:ok, %{conversations: %{}, stats: %{}}}
  end

  @impl true
  def handle_call({:add_message, conversation_id, message}, _from, state) do
    try do
      # Add timestamp and ensure unique ID
      enhanced_message = Map.merge(message, %{
        id: message[:id] || System.unique_integer([:positive]),
        timestamp: message[:timestamp] || DateTime.utc_now()
      })

      # Get existing messages for this conversation
      existing_messages = Map.get(state.conversations, conversation_id, [])
      
      # Enforce message limit per conversation
      trimmed_messages = if length(existing_messages) >= @max_messages_per_conversation do
        # Remove oldest messages to make room
        Enum.drop(existing_messages, length(existing_messages) - @max_messages_per_conversation + 1)
      else
        existing_messages
      end
      
      updated_messages = trimmed_messages ++ [enhanced_message]

      # Update conversation stats
      conversation_stats = %{
        message_count: length(updated_messages),
        last_activity: DateTime.utc_now(),
        created_at: get_in(state.stats, [conversation_id, :created_at]) || DateTime.utc_now()
      }

      # Update state
      updated_conversations = Map.put(state.conversations, conversation_id, updated_messages)
      updated_stats = Map.put(state.stats, conversation_id, conversation_stats)
      new_state = %{state | conversations: updated_conversations, stats: updated_stats}

      # Check if we need to cleanup old conversations
      new_state = maybe_cleanup_conversations(new_state)

      {:reply, {:ok, enhanced_message}, new_state}
    rescue
      error ->
        Logger.error("MessageStore error in add_message: #{inspect(error)}")
        {:reply, {:error, :internal_error}, state}
    end
  end

  @impl true
  def handle_call({:get_messages, conversation_id}, _from, state) do
    try do
      messages = Map.get(state.conversations, conversation_id, [])
      # Return messages in chronological order (oldest first)
      {:reply, {:ok, messages}, state}
    rescue
      error ->
        Logger.error("MessageStore error in get_messages: #{inspect(error)}")
        {:reply, {:error, :internal_error}, state}
    end
  end

  @impl true
  def handle_call({:get_conversation_stats, conversation_id}, _from, state) do
    stats = Map.get(state.stats, conversation_id, %{message_count: 0, last_activity: nil, created_at: nil})
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:get_conversation_count, _from, state) do
    count = map_size(state.conversations)
    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call({:get_conversation_context, conversation_id, limit}, _from, state) do
    messages = Map.get(state.conversations, conversation_id, [])
    stats = Map.get(state.stats, conversation_id, %{})
    
    recent_messages = Enum.take(messages, -limit)
    
    context = %{
      conversation_id: conversation_id,
      messages: recent_messages,
      stats: stats,
      total_messages: length(messages),
      participants: get_conversation_participants(messages),
      metadata: %{
        participants: get_conversation_participants(messages)
      }
    }
    
    {:reply, {:ok, context}, state}
  end

  @impl true
  def handle_call({:search_messages, conversation_id, query}, _from, state) do
    messages = Map.get(state.conversations, conversation_id, [])
    
    matching_messages = 
      messages
      |> Enum.filter(fn message ->
        content = Map.get(message, :content, "")
        String.contains?(String.downcase(content), String.downcase(query))
      end)
    
    {:reply, {:ok, matching_messages}, state}
  end

  @impl true
  def handle_call({:get_messages_by_role, conversation_id, role}, _from, state) do
    messages = Map.get(state.conversations, conversation_id, [])
    
    filtered_messages = 
      messages
      |> Enum.filter(fn message ->
        Map.get(message, :role) == role
      end)
    
    {:reply, {:ok, filtered_messages}, state}
  end

  @impl true
  def handle_call({:update_conversation_metadata, conversation_id, metadata}, _from, state) do
    current_stats = Map.get(state.stats, conversation_id, %{})
    updated_stats = Map.merge(current_stats, %{metadata: metadata})
    
    new_stats = Map.put(state.stats, conversation_id, updated_stats)
    new_state = %{state | stats: new_stats}
    
    {:reply, {:ok, :updated}, new_state}
  end

  @impl true
  def handle_call({:get_recent_messages, conversation_id, limit}, _from, state) do
    try do
      messages = Map.get(state.conversations, conversation_id, [])
      # Take the most recent messages (from the end of the list)
      recent_messages = messages
      |> Enum.take(-limit)
      
      {:reply, {:ok, recent_messages}, state}
    rescue
      error ->
        Logger.error("MessageStore error in get_recent_messages: #{inspect(error)}")
        {:reply, {:error, :internal_error}, state}
    end
  end

  @impl true
  def handle_call({:clear_conversation, conversation_id}, _from, state) do
    try do
      updated_conversations = Map.delete(state.conversations, conversation_id)
      updated_stats = Map.delete(state.stats, conversation_id)
      new_state = %{state | conversations: updated_conversations, stats: updated_stats}
      {:reply, {:ok, :cleared}, new_state}
    rescue
      error ->
        Logger.error("MessageStore error in clear_conversation: #{inspect(error)}")
        {:reply, {:error, :internal_error}, state}
    end
  end

  @impl true
  def handle_cast(:cleanup_old_conversations, state) do
    new_state = cleanup_old_conversations_impl(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    try do
      Logger.info("MessageStore: Running periodic cleanup")
      new_state = cleanup_old_conversations_impl(state)
      schedule_cleanup()
      {:noreply, new_state}
    rescue
      error ->
        Logger.error("MessageStore error during cleanup: #{inspect(error)}")
        # Continue with original state if cleanup fails
        schedule_cleanup()
        {:noreply, state}
    end
  end



  @impl true
  def handle_info(:validate_state, state) do
    try do
      # Validate state integrity
      validated_state = validate_and_repair_state(state)
      {:noreply, validated_state}
    rescue
      error ->
        Logger.error("MessageStore state validation failed: #{inspect(error)}")
        # Reset to clean state if validation fails completely
        clean_state = %{conversations: %{}, stats: %{}}
        {:noreply, clean_state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("MessageStore: Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    total_messages = 
      state.conversations
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.sum()
    
    stats = %{
       total_conversations: map_size(state.conversations),
       total_messages: total_messages,
       max_conversations: @max_conversations,
       max_messages_per_conversation: @max_messages_per_conversation,
       cleanup_interval_hours: trunc(@cleanup_interval / :timer.hours(1)),
       conversation_ttl_hours: trunc(@conversation_ttl / :timer.hours(1)),
       active_conversations: map_size(state.stats)
     }
     {:reply, {:ok, stats}, state}
   end

  @impl true
  def handle_cast(:cleanup_old_conversations, state) do
    current_time = System.system_time(:second)
    max_age_seconds = 24 * 60 * 60  # 24 hours
    
    # Remove conversations where all messages are older than max_age
    cleaned_conversations = state.conversations
    |> Enum.filter(fn {_conversation_id, messages} ->
      case messages do
        [] -> false
        [latest_message | _] ->
          message_age = current_time - Map.get(latest_message, :timestamp, current_time)
          message_age < max_age_seconds
      end
    end)
    |> Enum.into(%{})
    
    removed_count = map_size(state.conversations) - map_size(cleaned_conversations)
    
    if removed_count > 0 do
      Logger.info("Cleaned up #{removed_count} old conversations")
    end
    
    new_state = %{state | conversations: cleaned_conversations}
    schedule_cleanup()  # Schedule next cleanup
    
    {:noreply, new_state}
  end



  # Private functions

  defp maybe_cleanup_conversations(state) do
    try do
      conversation_count = map_size(state.conversations)
      
      if conversation_count > @max_conversations do
        Logger.info("MessageStore: Triggering cleanup due to conversation limit (#{conversation_count}/#{@max_conversations})")
        cleanup_old_conversations_impl(state)
      else
        state
      end
    rescue
      error ->
        Logger.error("MessageStore error in maybe_cleanup_conversations: #{inspect(error)}")
        # Return original state if cleanup fails
        state
    end
  end

  defp cleanup_old_conversations_impl(state) do
    current_time = DateTime.utc_now()
    
    # Find conversations older than TTL
    expired_conversations = 
      state.stats
      |> Enum.filter(fn {_id, stats} ->
        case stats.last_activity do
          nil -> true
          last_activity ->
            DateTime.diff(current_time, last_activity, :millisecond) > @conversation_ttl
        end
      end)
      |> Enum.map(fn {id, _stats} -> id end)
    
    # If we still have too many conversations, remove oldest ones
    conversations_to_remove = if map_size(state.conversations) - length(expired_conversations) > @max_conversations do
      # Sort by last activity and take oldest
      oldest_conversations = 
        state.stats
        |> Enum.reject(fn {id, _stats} -> id in expired_conversations end)
        |> Enum.sort_by(fn {_id, stats} -> stats.last_activity || DateTime.from_unix!(0) end)
        |> Enum.take(@message_cleanup_batch_size)
        |> Enum.map(fn {id, _stats} -> id end)
      
      expired_conversations ++ oldest_conversations
    else
      expired_conversations
    end
    
    # Remove expired conversations
    updated_conversations = Map.drop(state.conversations, conversations_to_remove)
    updated_stats = Map.drop(state.stats, conversations_to_remove)
    
    if length(conversations_to_remove) > 0 do
      Logger.info("MessageStore: Cleaned up #{length(conversations_to_remove)} old conversations")
    end
    
    %{state | conversations: updated_conversations, stats: updated_stats}
   end

   defp get_conversation_participants(messages) do
     messages
     |> Enum.map(fn message -> Map.get(message, :role, :unknown) end)
     |> Enum.uniq()
   end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp validate_and_repair_state(state) do
    # Ensure conversations is a map
    conversations = case state.conversations do
      conversations when is_map(conversations) -> conversations
      _ -> 
        Logger.warning("MessageStore: Repairing invalid conversations state")
        %{}
    end

    # Ensure stats is a map
    stats = case state.stats do
      stats when is_map(stats) -> stats
      _ -> 
        Logger.warning("MessageStore: Repairing invalid stats state")
        %{}
    end

    # Remove any conversations with invalid message lists
    valid_conversations = conversations
    |> Enum.filter(fn {_id, messages} -> is_list(messages) end)
    |> Enum.into(%{})

    # Remove stats for conversations that no longer exist
    valid_stats = stats
    |> Enum.filter(fn {id, _stats} -> Map.has_key?(valid_conversations, id) end)
    |> Enum.into(%{})

    # Rebuild stats for conversations missing them
    complete_stats = valid_conversations
    |> Enum.reduce(valid_stats, fn {id, messages}, acc ->
      if Map.has_key?(acc, id) do
        acc
      else
        Map.put(acc, id, %{
          message_count: length(messages),
          last_activity: DateTime.utc_now(),
          created_at: DateTime.utc_now()
        })
      end
    end)

    repaired_state = %{conversations: valid_conversations, stats: complete_stats}
    
    if repaired_state != state do
      Logger.info("MessageStore: State repaired successfully")
    end
    
    repaired_state
  end
end