# Auto-Invite

## Purpose

Streamline raid formation by automating the invite, convert, and promote workflow. The raid leader enables whisper-based invites so players can request an invite by whispering a keyword, mass-invites guild members by rank, and auto-promotes designated players to assistant when they join.

This replaces the invite features from MRT's `InviteTool.lua`. All of these features operate outside instances, so Midnight's Secret Values restrictions do not apply.

## Features

### 1. Whisper-Keyword Invite

When enabled, PRT listens for incoming whispers that match a configurable keyword list. When a match is found, PRT invites the sender.

**Matching rules:**
- The incoming message is lowercased and trimmed of leading/trailing whitespace before comparison.
- The match checks whether the trimmed message exactly equals one of the configured keywords. It is not a substring match—a whisper of "invite me please" does not match the keyword "inv".
- Default keywords: `inv`, `invite`, `123`.

**In-game whispers (`CHAT_MSG_WHISPER`):**
- Extract the sender name from the event.
- If the guild-only filter is enabled, check whether the sender is in the guild. If not, ignore the whisper.
- If the sender is already in the group, ignore the whisper.
- Invite via `C_PartyInfo.InviteUnit(senderName)`.

**BNet whispers (`CHAT_MSG_BN_WHISPER`):**
- The event provides a `bnetIDAccount` for the sender.
- Look up the sender's game accounts via `C_BattleNet.GetFriendAccountInfo` to find their `bnetAccountID`, then enumerate game accounts via `C_BattleNet.GetFriendNumGameAccounts` / `C_BattleNet.GetFriendGameAccountInfo`.
- Find the game account that is online and playing WoW Retail (check `clientProgram == "WoW"` and the account is in the correct region/realm).
- If the guild-only filter is enabled, check whether the character name from the game account info is in the guild. If not, ignore.
- Invite via `BNInviteFriend(gameAccountID)`.
- If no matching WoW game account is found (the friend is on a different Blizzard game, or offline in WoW), ignore the whisper.

### 2. Guild Rank Mass Invite

A one-shot action that scans the guild roster and invites all online members whose rank matches the selected ranks.

**How it works:**
1. Scan the guild roster via `GetNumGuildMembers()` / `GetGuildRosterInfo(i)`.
2. For each online member whose rank is checked in the configuration, and who is not already in the group, queue an invite.
3. Process invites, handling the party-to-raid conversion as needed (see auto-convert below).

**Rank selection:**
- The configuration displays all guild ranks as checkboxes. Rank names and count are read from the guild roster API at display time—they are not hardcoded.
- Selected ranks are stored by rank index (0-based, where 0 is Guild Master), not by name, since rank names can change.
- The mass invite is triggered by a button press. It is not automatic or recurring—pressing the button scans once and invites everyone matching.

### 3. Auto-Convert to Raid

When an invite would cause the group to exceed 5 members, PRT must convert the party to a raid before the invite can succeed.

**Behavior:**
1. Before sending an invite, check `GetNumGroupMembers()`.
2. If the group has 4 or more members and is still a party (`not IsInRaid()`), call `C_PartyInfo.ConvertToRaid()`.
3. The conversion is not instant. PRT must wait for `GROUP_ROSTER_UPDATE` to confirm the group is now a raid before sending the pending invite.
4. Pending invites are stored in a queue. When `GROUP_ROSTER_UPDATE` fires and `IsInRaid()` is true, PRT processes the queue.
5. If multiple invites arrive while the conversion is in progress, they all go into the queue and are processed once the conversion completes.

### 4. Auto-Promote

Designated players are automatically promoted to raid assistant when they join the group.

**How it works:**
- The configuration holds a comma-separated list of player names.
- On `GROUP_ROSTER_UPDATE`, PRT scans the raid roster for any newly joined members whose name matches the promote list.
- Matching players are promoted via `PromoteToAssistant(unit)`.
- PRT must track which players are already in the group to distinguish new joins from other roster changes (e.g., role changes, disconnects). A simple "known members" set, rebuilt on each roster update, is sufficient—if a name is in the roster but not in the known set, it's a new join.
- The promote list uses the same name format as auto-marking: character name, optionally with server for cross-realm (e.g., `"Niv-Stormrage"`). Case-insensitive matching.
- The player must be raid leader to promote. If not, the promote is silently skipped (same pattern as auto-marking).

## Edge Cases

### Duplicate Invites

If a player whispers the keyword multiple times before being invited (or while the conversion is in progress), PRT should not send duplicate invites. Check whether the player is already in the group or already in the pending invite queue before adding them.

### Sender Already in Group

If someone already in the group whispers the keyword, ignore it. Don't send an invite, don't print an error.

### BNet Friend with Multiple WoW Accounts

A BNet friend may have multiple WoW accounts (e.g., a retail and a classic account). PRT should find the account that is currently online and playing WoW Retail. If multiple retail accounts are online (uncommon), pick the first one found.

### Guild Roster Not Loaded

`GetGuildRosterInfo` may return stale or incomplete data if the guild roster hasn't been queried recently. Before mass invite, PRT should call `GuildRoster()` (or `C_GuildInfo.GuildRoster()`) to request a roster update, then process invites on the subsequent `GUILD_ROSTER_UPDATE` event. This adds a small delay but ensures accurate data.

### Whisper During Active Encounter

Whisper events still fire during encounters, but inviting someone mid-fight is unusual. PRT does not need to block this—`C_PartyInfo.InviteUnit` is not restricted by Secret Values (it's not addon messaging or combat data). If the API fails for some other reason, the failure is silent.

### Mass Invite with Large Guild

If many guild members match the selected ranks, PRT may need to send many invites in quick succession. The WoW client may throttle or fail some of these. PRT should process invites with a small delay between each (e.g., stagger them slightly) rather than firing them all in a single frame. The exact throttle strategy is an implementation detail.

### Player Leaves and Rejoins (Auto-Promote)

If a player on the promote list leaves and rejoins, they should be promoted again. The "known members" set is rebuilt on each roster update, so a player who left will be absent from the set and treated as a new join when they return.

## Configuration

### Config Tab: "Auto-Invite"

A new tab in the PRT config frame.

**Whisper Invite Section**
- Enable/disable checkbox for whisper invites
- Keywords text field (space-delimited, e.g., `inv invite 123`)
- Guild-only toggle checkbox

**Guild Invite Section**
- Header or label explaining this is a one-shot mass invite
- A checkbox for each guild rank (dynamically populated from the guild roster)
- "Invite by Rank" button that triggers the mass invite

**Auto-Promote Section**
- Enable/disable checkbox for auto-promote
- Player names text field (comma-separated)

### Settings Storage

Settings are stored per-profile under `PRT:GetSetting("autoInvite")`:

```
PRT.defaults.autoInvite = {
    whisperInviteEnabled = true,
    keywords = "inv invite 123",
    guildOnly = false,
    inviteRanks = {},       -- table of rank index → boolean, populated dynamically
    promoteEnabled = true,
    promoteNames = "",      -- comma-separated player names
}
```

`inviteRanks` is a table keyed by rank index (0 = Guild Master, 1 = next rank, etc.) with boolean values. It is populated the first time the config tab is opened and the guild roster is available. Ranks that don't exist in the table are treated as unchecked.

## Module Structure

Follows the existing module pattern:

- `PRT.AutoInvite = {}`
- Defaults on `PRT.defaults`
- `Initialize` function on `ADDON_LOADED` that registers for `CHAT_MSG_WHISPER`, `CHAT_MSG_BN_WHISPER`, and `GROUP_ROSTER_UPDATE`
- Config tab via `PRT:RegisterTab`
- Listed in `PurplexityRaidTools.toc` as `Modules/AutoInvite.lua`

### Key APIs

**Inviting:**
- `C_PartyInfo.InviteUnit(name)` — invite a character by name
- `BNInviteFriend(gameAccountID)` — invite a BNet friend's game account
- `C_PartyInfo.ConvertToRaid()` — convert party to raid

**BNet lookup:**
- `C_BattleNet.GetFriendAccountInfo(friendIndex)` — BNet friend info
- `C_BattleNet.GetFriendNumGameAccounts(friendIndex)` — count of game accounts
- `C_BattleNet.GetFriendGameAccountInfo(friendIndex, accountIndex)` — specific game account info
- `BNGetNumFriends()` — total BNet friend count for iteration

**Guild roster:**
- `GetNumGuildMembers()` — guild member count
- `GetGuildRosterInfo(index)` — individual member info (name, rank, rankIndex, online, etc.)
- `GuildRoster()` or `C_GuildInfo.GuildRoster()` — request a roster refresh

**Group management:**
- `GetNumGroupMembers()` — current group size
- `IsInRaid()` — whether the group is a raid
- `UnitIsGroupLeader("player")` — leader check for promote
- `PromoteToAssistant(unit)` — promote a player to raid assistant
- `GetRaidRosterInfo(i)` — raid roster scanning

**Events:**
- `CHAT_MSG_WHISPER` — in-game whisper received
- `CHAT_MSG_BN_WHISPER` — BNet whisper received
- `GROUP_ROSTER_UPDATE` — group composition changed (for convert-to-raid queue processing and auto-promote)
- `GUILD_ROSTER_UPDATE` — guild roster data refreshed (for mass invite after requesting roster)

### Helper: Guild Membership Check

PRT needs a `UnitInGuild(name)` helper for the guild-only filter. This scans the guild roster for a matching name. MRT had an equivalent at `ExRT.F.UnitInGuild`. This could be placed in the core namespace (`PRT.UnitInGuild`) if other modules ever need it, or kept local to the auto-invite module.
