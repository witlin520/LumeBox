# LumeBox media ownership patch

Based on audio_service 0.18.19 (MIT; upstream LICENSE retained).

Only changes Darwin remote-command/Now Playing coordination. Audiobook output
uses the unmodified just_audio + just_audio_background public interfaces.
The active app sound source is recorded in `lumebox.mediaOwner` by the shared
focus channel. When another source owns playback, audio_service does not clear
or replace its controls/metadata, and stale audiobook controls reject actions.
When audiobooks reclaim ownership, their controls are rebuilt with only this
plugin target removed/re-added, because the existing video controller clears
all MPRemoteCommand targets when handing off. Android and Dart plugin behavior
is unchanged. No audioplayers implementation is included.
