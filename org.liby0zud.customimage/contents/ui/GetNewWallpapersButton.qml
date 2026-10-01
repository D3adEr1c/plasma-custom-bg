import org.kde.newstuff as NewStuff

NewStuff.Button {
    signal wallpapersChanged()
    text: i18nd("plasma_wallpaper_org.liby0zud.customimage", "Get New Wallpapers…")
    configFile: "wallpaper.knsrc"
    onEntryEvent: (entry, event) => {
        if (event === NewStuff.Entry.StatusChangedEvent) wallpapersChanged();
    }
}
