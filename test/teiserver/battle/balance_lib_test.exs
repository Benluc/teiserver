defmodule Teiserver.Battle.BalanceLibTest do
  use Central.DataCase, async: true
  alias Teiserver.Battle.BalanceLib
  # alias Teiserver.TeiserverTestLib

  test "loser picks simple users" do
    result = BalanceLib.create_balance(
      [
        %{1 => 5},
        %{2 => 6},
        %{3 => 7},
        %{4 => 8},
      ],
      2,
      mode: :loser_picks
    )
    |> Map.drop([:logs, :time_taken])

    assert result == %{
      team_groups: %{
        1 => [
          %{members: [4], count: 1, group_rating: 8, ratings: [8]},
          %{members: [1], count: 1, group_rating: 5, ratings: [5]}],
        2 => [
          %{members: [3], count: 1, group_rating: 7, ratings: [7]},
          %{members: [2], count: 1, group_rating: 6, ratings: [6]}
        ]
      },
      team_players: %{
        1 => [4, 1],
        2 => [3, 2]
      },
      ratings: %{
        1 => 13,
        2 => 13
      },
      captains: %{
        1 => 4,
        2 => 3
      },
      team_sizes: %{
        1 => 2,
        2 => 2
      },
      deviation: 0
    }
  end

  test "loser picks simple group" do
    result = BalanceLib.create_balance(
      [
        %{4 => 5, 1 => 8},
        %{2 => 6},
        %{3 => 7}
      ],
      2,
      mode: :loser_picks,
      rating_lower_boundary: 100,
      rating_upper_boundary: 100,
      mean_diff_max: 100,
      stddev_diff_max: 100
    )
    |> Map.drop([:logs, :time_taken])

    assert result == %{
      team_groups: %{
        1 => [
          %{count: 2, group_rating: 13, members: [2, 3], ratings: [6, 7]}
        ],
        2 => [
          %{count: 2, group_rating: 13, members: [1, 4], ratings: [8, 5]}
        ]
      },
      team_players: %{
        1 => [2, 3],
        2 => [1, 4]
      },
      ratings: %{
        1 => 13,
        2 => 13
      },
      captains: %{
        1 => 2,
        2 => 1
      },
      team_sizes: %{
        1 => 2,
        2 => 2
      },
      deviation: 0
    }
  end

  test "loser picks bigger game group" do
    result = BalanceLib.create_balance(
      [
        # Two high tier players partied together
        %{101 => 41, 102 => 35},

        # A bunch of mid-low tier players together
        %{103 => 20, 104 => 17, 105 => 13.5},

        # A smaller bunch of even lower tier players
        %{106 => 15, 107 => 7.5},

        # Other players, a range of ratings
        %{108 => 31},
        %{109 => 26},
        %{110 => 25},
        %{111 => 21},
        %{112 => 19},
        %{113 => 16},
        %{114 => 16},
        %{115 => 14},
        %{116 => 8}
      ],
      2,
      mode: :loser_picks,
      rating_lower_boundary: 5,
      rating_upper_boundary: 5,
      mean_diff_max: 5,
      stddev_diff_max: 5
    )

    # IO.puts result.logs |> Enum.join("\n")

    assert Map.drop(result, [:logs, :time_taken]) == %{
      captains: %{1 => 114, 2 => 106},
      deviation: 4,
      ratings: %{1 => 165.5, 2 => 159.5},
      team_groups: %{
        1 => [
          %{count: 2, group_rating: 24, members: [114, 116], ratings: [16, 8]},
          %{count: 3, group_rating: 50.5, members: 'ghi', ratings: [20, 17, 13.5]},
          %{count: 1, group_rating: 35, members: [102], ratings: [35]},
          %{count: 1, group_rating: 31, members: 'l', ratings: [31]},
          %{count: 1, group_rating: 25, members: [110], ratings: [25]}
        ],
        2 => [
          %{count: 2, group_rating: 22.5, members: [106, 107], ratings: [15, 7.5]},
          %{count: 3, group_rating: 51, members: 'oqs', ratings: [21, 16, 14]},
          %{count: 1, group_rating: 41, members: 'e', ratings: [41]},
          %{count: 1, group_rating: 26, members: 'm', ratings: [26]},
          %{count: 1, group_rating: 19, members: 'p', ratings: [19]}
        ]
      },
      team_players: %{1 => [114, 116, 103, 104, 105, 102, 108, 110], 2 => [106, 107, 111, 113, 115, 101, 109, 112]},
      team_sizes: %{1 => 8, 2 => 8}
    }
  end

  test "smurf party" do
    result = BalanceLib.create_balance(
      [
        # Our smurf party
        %{101 => 51, 102 => 10, 103 => 10},

        # Other players, a range of ratings
        %{104 => 35},
        %{105 => 34},
        %{106 => 29},
        %{107 => 28},
        %{108 => 27},
        %{109 => 26},
        %{110 => 25},
        %{111 => 21},
        %{112 => 19},
        %{113 => 16},
        %{114 => 15},
        %{115 => 14},
        %{116 => 8}
      ],
      2,
      mode: :loser_picks
    )

    # IO.puts result.logs |> Enum.join("\n")

    assert Map.drop(result, [:logs, :time_taken]) == %{
      captains: %{1 => 101, 2 => 104},
      deviation: 0,
      ratings: %{1 => 184, 2 => 184},
      team_groups: %{
        1 => [
          %{count: 1, group_rating: 51, members: [101], ratings: [51]},
          %{count: 1, group_rating: 29, members: [106], ratings: [29]},
          %{count: 1, group_rating: 27, members: [108], ratings: [27]},
          %{count: 1, group_rating: 25, members: [110], ratings: [25]},
          %{count: 1, group_rating: 19, members: [112], ratings: [19]},
          %{count: 1, group_rating: 15, members: [114], ratings: [15]},
          %{count: 1, group_rating: 10, members: [102], ratings: [10]},
          %{count: 1, group_rating: 8, members: [116], ratings: [8]}
        ],
        2 => [
          %{count: 1, group_rating: 35, members: [104], ratings: '#'},
          %{count: 1, group_rating: 34, members: [105], ratings: [34]},
          %{count: 1, group_rating: 28, members: [107], ratings: [28]},
          %{count: 1, group_rating: 26, members: [109], ratings: [26]},
          %{count: 1, group_rating: 21, members: [111], ratings: [21]},
          %{count: 1, group_rating: 16, members: [113], ratings: [16]},
          %{count: 1, group_rating: 14, members: [115], ratings: [14]},
          %{count: 1, group_rating: 10, members: [103], ratings: '\n'}
        ]
      },
      team_players: %{1 => 'ejlnprft', 2 => 'hikmoqsg'},
      team_sizes: %{1 => 8, 2 => 8}
    }
  end
end
