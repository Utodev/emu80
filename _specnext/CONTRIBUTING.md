# Contributing to TBBlue #

You found your way here thanks to your interest in the **ZX Spectrum Next** project and/or retrocomputing in general! That's _great_ but if you wish to contribute there are certain guidelines that need to be followed. Here are the specifics:


### 1. TBBlue is open but not necessarily fully open sourced.  ###

This means that you may find the source for **MANY**, but not **ALL** pieces of software here. This stems directly from SpecNext Ltd's license to use the Sinclair name.  
Remember this is a collection of software but not a software itself. It also contains *documents*, *images* and *other media* and therefore should not be considered in the same vein as one piece of software because it's not. This also allows contributors to choose their own license; you can contribute something that's **GPL 3**, **MIT**, something else, be in the **public domain** or alternatively **fully closed-source**.  

### 2. All ROM images contained herewith with the exception of the NextZXOS MF and divMMC modules are copyrighted Amstrad / Sky plc or are jointly copyrighted by Amstrad and their author (ie NextZXOS, LG, GW ROMS)  ###

This means that if you wish to contribute a ROM image you either need to have permission by Amstrad / Sky plc to do so, own the work or have express permission to do so. In all cases other than the rom images provided by SpecNext Ltd you will need to include the license in the **/docs/licenses** folder with your **full name** and **redacted email** (which you will have to provide to SpecNext Ltd for idemnification)  

### 3. If you fork or want to distribute the project you need to abide by 1. and 2. above.  ###

This means that if you decide to fork, you can only fork the parts for which express permission has been given by their respective license or directly by their authors. For example in order to distribute the LG rom, you will need to contact its author first AND Amstrad/Sky plc. Also as a second example, you can fork/distribute almost all contents of the **/dot/** folder.  
  
### 4. No open sourced software contained herewith must be distributed without observing the terms of its license.  ###
  
This means that you're responsible to distribute all sources together with the executables in for example the cases of GPL-complying software. The general rule is: respect the rights of the other authors.

### 5. If you contribute software maintain the folder organization ###

This means: put your application where it should go; For a game put it under **games/&lt;platform>/&lt;nameofgame>** for a tool under **tools/&lt;type of tool>/&lt;name_of_tool>**, store the documents under **/docs/** (follow the structure; it's quite easy) and if you can put a small **readme.txt** file in the folder with your application. dot commands should go under **/dot/** and anything extra pertaining to them (or versions specifically made for esxDOS but carry the same name) should go under **/dot/extra/**  
  
### 6. If you contribute software update the changelog and wiki. ###  

Don't forget to update the changelog and wiki pages; it's important as the distribution grows!  

### 7. Do not modify the System folders and files: /nextzxos, /tbblue, /tbblue/config.ini and /TBBLUE.FW ###
  
If you suggest a modification to any system file and/or folder add it as a *basename-&lt;name_of_file>.&lt;ext>* with clear instructions on how and where it should be merged by the user. The distribution **must be operable at all times** ergo the system folders and files must not be disturbed from their working state. End-users expect the distribution to be downloaded straight to their SD cards and booted directly from there. If in doubt confer with the rest of the contributors. Only authors of specific extensions/rom images/drivers that have been previously vetted as working can proceed to modify files in the system folder after they confer with the OS maintainer (Garry Lancaster) and the TBBlue main maintainer (Phoebus Dokos).

### 8. If you contribute software without a stated license, this is considered closed source without source code and open source if it includes sources under /src ###

This means that if you do not include a license file under **/docs/licenses/** but without source code under **/src/** your work will be automatically considered first as **further distribution denied** or in the second case as **open source/further distribution granted**  
  
### 9. All the software / documentation you contribute belongs to you unless you state otherwise ###  

This means that you retain the copyright of all the works you contribute herewith and you can at any given moment choose to remove it from the distribution without explanation or without any ramification except if you've given up on this right when you initially contribute (in which case you will have stated so in the accompanying license).

### 10. You cannot remove or modify software in the distribution belonging to others if its license does not allow so, if you lack permission ###  

This means, that if another author has contributed software to the distribution, you cannot remove it or modify it without his/her express permission (except in cases outlined in #11 below) if the software's license doesn't allow so. Excepted from the above is the current principal maintainer of the distribution (At the time of writing Phoebus Dokos) who has permission to remove software as well as modify the organisation of the distribution in order to maintain license compliance and usability. Eg. the principal maintainer is allowed to remove illegal software, to remove incompatible software, to update software versions (modification) but is **not** allowed to remove software altogether without first acquiring permission from the author if the aforementioned cases are not true. This ensures that the distribution is at all times impartial in its governance.
  
### 11. Software that was contributed illegally shall be removed without explanation ###  
  
Basically, what this means is that if you contribute anything that's not legal and could violate the Sinclair license from Amstrad / Sky plc will be removed immediately when found. If you are in the team of maintainers then you CAN remove someone else's contribution if it's in violation of a license or copyright law.
  
### 12. Core contributions MUST observe Intellectual Property laws ###  

Since this is the **official** distribution, it cannot contain material that it's illegal, trademarked and distributed without permission or have a license that does not allow distribution. You can however post VHDL source code as long as the core is not built. Since the above doesn't make much sense without examples let's give examples

  * You **cannot** contribute a core synthesising wholly denied IP. For example you cannot contribute a Jupiter Ace core. You can distribute VHDL code that could be used to synthesise it but not the core itself.  
  * You **cannot** contribute a core synthesising partly denied IP. For example you cannot contribute a modified Spectrum Next core that has a synthesised clone of a Yamaha&trade; FM audio Sound Generator.  You can also here contribute VHDL that can be used to synthesise it.  
  * You **can** contribute a core for which you have obtained permission to distribute.  
  * You **cannot** contribute a core for a machine that violated IP laws in the first place. Eg. You cannot contribute a Microdigital TK core  
  * You **can** contribute a core containing hardware functionality that was created in *clean-room* conditions. However you **cannot** distribute any rom image that addresses it that may be copyrighted if you do not possess an express permission.  
  * You **can** contribute a core of a system that's *status-uknown* but you must also be prepared for it to be removed from the official distribution if it's found in violation of any IP law.   
  
The IP laws governing the TBBlue distribution are the IP laws of the United Kingdom at the time of this writing (September 2018).  

### 13. You can use the entirety of the distribution in other projects if it's unchanged but these projects cannot hold the Sincair or Next names ###  

This is not actually part of the contribution guidelines but it's also a good place to mention. This distribution contains VHDL and schematics to build a system 100% compatible to the **ZX Spectrum Next**. This is not only 100% legal as this is a fully open system, it's even encouraged in the spirit of innovation always born from the *Sinclair* legacy, however due to licensing restrictions the following need apply:  
  * You *cannot* use either the **ZX Spectrum Next** or **Sinclair** names or any combination of them thereof, as these are trademarked by their respective owners and their usage is governed by license agreements and IP laws.  
  * If you create your own machine based on the schematics and code included herewith, you can refer to it with your **own chosen name**, as **ZX Next-Compatible** or **TBBlue-compatible**.   
  * You **cannot** use the **Sinclair** logo in any boot screen, advertising or promotional material if it's not an _actual_ **ZX Spectrum Next** (cased or in board-only form) produced by **SpecNext Ltd**. You are additionally required to display the TBBlue logo upon boot on your machines/emulators that incorporate all **ZX Spectrum Next** features.  
  
### 14. By contributing to the TBBlue distribution you're acknowledging that all the above are in-force and that you agree to them ###  

This is self-explanatory we believe and it's the easiest way to bypass all the otherwise-required legalese  




