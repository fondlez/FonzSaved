# Changelog for "FonzSaved" and "FonzSavedFu"

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.4] - 2023-11-18

### Fixed

- [General] addon metadata errors corrected.

## [1.1.3] - 2023-11-18

### Fixed

- [General] setting the language option is now correctly everywhere per realm 
account, not per character.

## [1.1.2] - 2023-11-17

### Fixed

- [Lockout] lockout checks when zoning into the world or changing major zones
and instances now more reliable.

## [1.1.1] - 2023-11-17

### Added

- [Lockout] spam protection for instance reset chat announcement and addon
broadcast. Duration set to protect against spam from multiple instances 
being reset.

## [1.1.0] - 2023-11-16

### Added

- [General] date-times can now be customized to one of many different common
formats, e.g. US Civilian, US Military, Germany, China.
- [Raid Leader Saved] an addon query for saved raids to the raid leader when 
entering a raid group or becoming a member of a newly converted raid.
- [Lockout] chat announcement and addon broadcast when a group leader resets
normal instances via "Reset all instances" character portrait option or the
WoW API command `/run ResetInstances()`.
- [Lockout] option to toggle whether to announce resets to group chat. An addon
broadcast is still always sent.
- [Lockout] ability to add an instance manually using the `/lockout add`
(or `/lad`) command.
- [Lockout] ability to delete an instance using the `/lockout del` command.
- [Lockout] ability to wipe all instances using the `/lockout wipe` command.
- [Lockout] new alias commands for `/lockout`: `/instance` or `/instances`.
- [Lockout] option to notify of new instances in the past hour. Methods: 
system "chat", system "error" and "none". Default: "chat".

### Changed

- [General] the language option is now per realm account, not per character.
- [Lockout] instances no longer disappear after an hour. A history is kept
up to a customizable number limit, by default 32 entries, maximum of 60 entries.
- [Lockout] instances are now color-coded by how long ago they were entered.
Entries in the past hour, past 24 hours and post-24 hours are colored 
differently.

### Fixed

- [Lockout] a check when logging into the world while inside an instance and 
part of a group was incorrectly creating a new lockout.

## [1.0.0] - 2023-11-09

### Added

- Initial public release.