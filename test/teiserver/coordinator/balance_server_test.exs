defmodule Teiserver.Coordinator.BalanceServerTest do
  use Central.ServerCase, async: false
  alias Teiserver.Battle.Lobby
  alias Teiserver.Account.ClientLib
  alias Teiserver.Common.PubsubListener
  alias Teiserver.Game.MatchRatingLib
  alias Teiserver.{Account, Battle, User, Client, Coordinator}
  alias Teiserver.Coordinator.ConsulServer

  import Teiserver.TeiserverTestLib,
    only: [tachyon_auth_setup: 0, _tachyon_send: 2, _tachyon_recv: 1, _tachyon_recv_until: 1]

  setup do
    Coordinator.start_coordinator()
    %{socket: hsocket, user: host} = tachyon_auth_setup()
    %{socket: psocket, user: player} = tachyon_auth_setup()

    # User needs to be a moderator (at this time) to start/stop Coordinator mode
    User.update_user(%{host | moderator: true})
    ClientLib.refresh_client(host.id)

    lobby_data = %{
      cmd: "c.lobby.create",
      name: "Coordinator #{:rand.uniform(999_999_999)}",
      nattype: "none",
      port: 1234,
      game_hash: "string_of_characters",
      map_hash: "string_of_characters",
      map_name: "koom valley",
      game_name: "BAR",
      engine_name: "spring-105",
      engine_version: "105.1.2.3",
      settings: %{
        max_players: 16
      }
    }
    data = %{cmd: "c.lobby.create", lobby: lobby_data}
    _tachyon_send(hsocket, data)
    [reply] = _tachyon_recv(hsocket)
    lobby_id = reply["lobby"]["id"]

    listener = PubsubListener.new_listener(["legacy_battle_updates:#{lobby_id}"])

    # Player needs to be added to the battle
    Lobby.add_user_to_battle(player.id, lobby_id, "script_password")
    player_client = Account.get_client_by_id(player.id)
    Client.update(%{player_client | player: true}, :client_updated_battlestatus)

    # Add user message
    _tachyon_recv_until(hsocket)

    # Battlestatus message
    _tachyon_recv_until(hsocket)

    {:ok, hsocket: hsocket, psocket: psocket, host: host, player: player, lobby_id: lobby_id, listener: listener}
  end

  test "server balance - simple", %{lobby_id: lobby_id, host: _host, psocket: _psocket, player: player} do
    # We don't want to use the player we start with, we want to number our players specifically
    Lobby.remove_user_from_any_lobby(player.id)

    %{user: u1} = ps1 = tachyon_auth_setup()
    %{user: u2} = ps2 = tachyon_auth_setup()
    %{user: u3} = ps3 = tachyon_auth_setup()
    %{user: u4} = ps4 = tachyon_auth_setup()
    %{user: u5} = ps5 = tachyon_auth_setup()
    %{user: u6} = ps6 = tachyon_auth_setup()
    %{user: u7} = ps7 = tachyon_auth_setup()
    %{user: u8} = ps8 = tachyon_auth_setup()

    rating_type_id = MatchRatingLib.rating_type_name_lookup()["Team"]

    [ps1, ps2, ps3, ps4, ps5, ps6, ps7, ps8]
    |> Enum.each(fn %{user: user, socket: socket} ->
      Lobby.force_add_user_to_lobby(user.id, lobby_id)
      :timer.sleep(50)# Need the sleep to ensure they all get added to the battle
      _tachyon_send(socket, %{cmd: "c.lobby.update_status", client: %{player: true, ready: true}})
    end)

    # Create some ratings
    # higher numbered players have higher ratings
    {:ok, _} = Account.create_rating(%{
      user_id: u1.id,
      rating_type_id: rating_type_id,
      rating_value: 20,
      skill: 20,
      uncertainty: 0,
      leaderboard_rating: 20,
      last_updated: Timex.now(),
    })

    {:ok, _} = Account.create_rating(%{
      user_id: u2.id,
      rating_type_id: rating_type_id,
      rating_value: 25,
      skill: 25,
      uncertainty: 0,
      leaderboard_rating: 25,
      last_updated: Timex.now(),
    })

    {:ok, _} = Account.create_rating(%{
      user_id: u3.id,
      rating_type_id: rating_type_id,
      rating_value: 30,
      skill: 30,
      uncertainty: 0,
      leaderboard_rating: 30,
      last_updated: Timex.now(),
    })

    {:ok, _} = Account.create_rating(%{
      user_id: u4.id,
      rating_type_id: rating_type_id,
      rating_value: 35,
      skill: 35,
      uncertainty: 0,
      leaderboard_rating: 35,
      last_updated: Timex.now(),
    })

    {:ok, _} = Account.create_rating(%{
      user_id: u5.id,
      rating_type_id: rating_type_id,
      rating_value: 36,
      skill: 36,
      uncertainty: 0,
      leaderboard_rating: 36,
      last_updated: Timex.now(),
    })

    {:ok, _} = Account.create_rating(%{
      user_id: u6.id,
      rating_type_id: rating_type_id,
      rating_value: 38,
      skill: 38,
      uncertainty: 0,
      leaderboard_rating: 38,
      last_updated: Timex.now(),
    })

    {:ok, _} = Account.create_rating(%{
      user_id: u7.id,
      rating_type_id: rating_type_id,
      rating_value: 47,
      skill: 47,
      uncertainty: 0,
      leaderboard_rating: 47,
      last_updated: Timex.now(),
    })

    {:ok, _} = Account.create_rating(%{
      user_id: u8.id,
      rating_type_id: rating_type_id,
      rating_value: 50,
      skill: 50,
      uncertainty: 0,
      leaderboard_rating: 50,
      last_updated: Timex.now(),
    })

    consul_state = Coordinator.call_consul(lobby_id, :get_all)
    max_player_count = ConsulServer.get_max_player_count(consul_state)
    assert max_player_count >= 8

    assert (Battle.list_lobby_players(lobby_id) |> Enum.count) == 8

    player_data = []
    bot_data = []
    team_count = 2

    balance_result = Coordinator.call_balancer(lobby_id, {
      :make_balance, player_data, bot_data, team_count
    })

    assert balance_result.team_players[1] == [u8.id, u5.id, u3.id, u2.id]
    assert balance_result.team_players[2] == [u7.id, u6.id, u4.id, u1.id]
    assert balance_result.deviation == {1, 1}
    assert balance_result.ratings == %{1 => 141.0, 2 => 140.0}
    assert Battle.get_lobby_balance_mode(lobby_id) == :grouped

    # It caches so calling it with the same settings should result in the same value
    assert Coordinator.call_balancer(lobby_id, {
      :make_balance, player_data, bot_data, team_count
    }) == balance_result

    # Party time, we start with the two highest rated players being put on the same team
    high_party = Account.create_party(u8.id)
    Account.move_client_to_party(u7.id, high_party.id)

    # Sleep so we don't get a cached list of players when calculating the balance
    :timer.sleep(520)

    party_balance_result = Coordinator.call_balancer(lobby_id, {
      :make_balance, player_data, bot_data, team_count
    })

    # First things first, it should be a different hash
    refute party_balance_result.hash == balance_result.hash

    assert party_balance_result.team_players[1] == [u8.id, u7.id, u3.id, u1.id]
    assert party_balance_result.team_players[2] == [u6.id, u5.id, u4.id, u2.id]
    assert party_balance_result.ratings == %{1 => 147.0, 2 => 134.0}
    assert party_balance_result.deviation == {1, 9}
    assert Battle.get_lobby_balance_mode(lobby_id) == :grouped

    # Now make an unfair party
    Account.move_client_to_party(u6.id, high_party.id)
    Account.move_client_to_party(u5.id, high_party.id)

    :timer.sleep(520)

    party_balance_result = Coordinator.call_balancer(lobby_id, {
      :make_balance, player_data, bot_data, team_count
    })

    # First things first, it should be a different hash
    refute party_balance_result.hash == balance_result.hash

    # Results should be the same as the first part of the test but with mode set to solo
    assert Battle.get_lobby_balance_mode(lobby_id) == :solo
    assert balance_result.team_players[1] == [u8.id, u5.id, u3.id, u2.id]
    assert balance_result.team_players[2] == [u7.id, u6.id, u4.id, u1.id]
    assert balance_result.ratings == %{1 => 141.0, 2 => 140.0}
    assert balance_result.deviation == {1, 1}
  end
end
