# ![Addon Icon](doc/icon.jpg) FonzSaved - World of Warcraft Addon

FonzSaved is an addon for World of Warcraft (TBC 2.4.3 client) to show saved and 
lockout instance information. It can also query saved instances (raids) of other 
players, if they have the addon installed.

FonzSavedFu is an optional graphical frontend for FonzSaved with a minimap icon 
and FuBar support. FuBar is not required.

## Core Features

### General
* Shows saved instance information across an account, e.g. for raids and 
heroic dungeons.
* Tracks and displays instance lockouts across an account. Entering an instance 
counts towards an account limit within a period of time, usually five per hour 
before being unable to enter any new instances with the error 
"You have entered too many instances recently.". Each new entry is a lockout.

### Raid Leader Saved (RLS)
* Announces when you as raid leader are saved to raids, as you create a new 
raid or when inviting others to the raid (with a cooldown for the announcement 
to prevent chat spam). It is disabled by default when inside an instance. 
Type `/rls` to toggle the feature temporarily or `/fsconfig rls enable` 
permanently.

### Query
* Can query the saved instance (raid) information of others who have the addon
installed.
* Can query by name, target or mouseover with the `/saved` command, e.g. for a target `/saved t`.
* Can query by name and raid name when only interested in a specific raid, e.g.
`/saved Gigachad Sunwell`.

### Chat
* Can announce saved instance (raid) information to any chat channel, e.g. guild `/saved g`.

## Slash Commands

* **Saved Instances**: `/saved` or `/fs`.
* **Instance Lockouts**: `/lockout` or `/locked`.
* **Options**: `/fsconfig` or `/fsoptions`.

## User Interface

### FonzSavedFu - Saved Instances
![FonzSavedFu - Saved Instances screenshot](doc/FonzSavedFu-saved-tooltip.jpg "FonzSavedFu - Saved Instances")

### FonzSaved - `/saved`
![FonzSaved - `/saved` screenshot](doc/FonzSaved-saved-command.jpg "FonzSaved - `/saved`")

### FonzSaved - `/saved ?`
![FonzSaved - `/saved ?` screenshot](doc/FonzSaved-saved-help.jpg "FonzSaved - `/saved ?`")

### FonzSavedFu - Instance Lockouts
![FonzSavedFu - Instance Lockouts screenshot](doc/FonzSavedFu-lockout-tooltip.jpg "FonzSavedFu - Instance Lockouts")

### FonzSavedFu - `/fsconfig` (or right click minimap icon)
![FonzSavedFu - Instance Lockouts screenshot](doc/FonzSavedFu-options.jpg "FonzSavedFu - options")

## Known Issues
* On a standard server there is no way to confirm instance lockout information.
This means it may be possible in some specific situations that fake additional 
lockouts are created by the addon. You can delete these lockouts with the 
`/locked del #` command where `#` is the lockout index.
* FonzSavedFu uses popular shared libraries for convenient graphical support. 
This means it is possible, though unlikely, for it to conflict with some other 
addons and generate error messages.
FonzSaved, the underlying addon with chat commands, does not have this problem
since it shares no code with any other addon.
* The addons do their best to offer multi-language support. However, some
information, e.g. the saved instance strings from `GetSavedInstanceInfo()`
WoW API command are not documented anywhere and are part of the WoW client. If 
you play with a client that is not enUS or enGB, you can modify the locale files 
for translations, e.g. the correct names for saved heroic dungeons
especially. If you also send the translations back to the [original project](https://github.com/fondlez/FonzSaved), 
it can greatly improve the addon for everyone in future!

## Motivation and Credits

### Motivation

A raid leader and others are organizing a new raid. A member enters the 
raid zone itself and does not notice that they become saved to that raid 
instance. Later, perhaps when all members are inside the raid zone, someone 
notices they are saved and now everyone is stuck with this raid instance ID, or 
until significant time and effort is made to contact a server admin to remove 
the unexpected raid instance ID from all invited players.

The original purpose - Raid Leader Saved (RLS) and Query modules - is 
to help prevent such a saved group forming as early as possible.

The original idea and implementation for this addon are by 
**[fondlez](https://github.com/fondlez)**.

### Credits
The parts of the addon for graphical display of saved instances and instance 
lockout tracking were inspired by:
* [SavedInstances](https://www.curseforge.com/wow/addons/saved_instances): the original TBC saved instance information addon.
* [Nova Instance Tracker](https://www.curseforge.com/wow/addons/nova-instance-tracker): the popular Retail/Classic instance lockout tracker.