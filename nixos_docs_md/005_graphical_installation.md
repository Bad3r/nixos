## Graphical Installation

The graphical installer is recommended for desktop users and will guide you through the installation.

1.  In the “Welcome” screen, you can select the language of the Installer and the installed system.

    ### Tip

    Leaving the language as “American English” will make it easier to search for error messages in a search engine or to report an issue.

2.  Next you should choose your location to have the timezone set correctly. You can actually click on the map!

    ### Note

    The installer will use an online service to guess your location based on your public IP address.

3.  Then you can select the keyboard layout. The default keyboard model should work well with most desktop keyboards. If you have a special keyboard or notebook, your model might be in the list. Select the language you are most comfortable typing in.

4.  On the “Users” screen, you have to type in your display name, login name and password. You can also enable an option to automatically login to the desktop.

5.  Then you have the option to choose a desktop environment. If you want to create a custom setup with a window manager, you can select “No desktop”.

    ### Tip

    If you don’t have a favorite desktop and don’t know which one to choose, you can stick to either GNOME or Plasma. They have a quite different design, so you should choose whichever you like better. They are both popular choices and well tested on NixOS.

6.  You have the option to allow unfree software in the next screen.

7.  The easiest option in the “Partitioning” screen is “Erase disk”, which will delete all data from the selected disk and install the system on it. Also select “Swap (with Hibernation)” in the dropdown below it. You have the option to encrypt the whole disk with LUKS.

    ### Note

    At the top left you see if the Installer was booted with BIOS or UEFI. If you know your system supports UEFI and it shows “BIOS”, reboot with the correct option.

    ### Warning

    Make sure you have selected the correct disk at the top and that no valuable data is still on the disk! It will be deleted when formatting the disk.

8.  Check the choices you made in the “Summary” and click “Install”.

    ### Note

    The installation takes about 15 minutes. The time varies based on the selected desktop environment, internet connection speed and disk write speed.

9.  When the install is complete, remove the USB flash drive and reboot into your new system!
