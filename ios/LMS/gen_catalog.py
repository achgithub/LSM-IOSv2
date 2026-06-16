#!/usr/bin/env python3
"""Generates LMS/Localizable.xcstrings from a curated translation table.

Source language is English (the key is the English string). We add es/de/fr/nl/it.
Tone: friendly/informal (tú/du/tu(fr)/je/tu) to match a casual football-pool app.
Football domain terms: round=ronda/Runde/manche/ronde/turno, pick=selección/Tipp/
choix/keuze/scelta, fixtures=partidos/Spiele/matchs/wedstrijden/partite,
standings=clasificación/Tabelle/classement/stand/classifica,
matchday=jornada/Spieltag/journée/speeldag/giornata.
Symbols / pure-data keys (v, —, •, ⚑, ×, %lld, A–Z, OK, watermark) are intentionally
omitted so they fall back to the source string in every language.
"""
import json, collections

# key -> (es, de, fr, nl, it)
T = collections.OrderedDict()
def add(key, es, de, fr, nl, it):
    T[key] = (es, de, fr, nl, it)

# ---- Tabs / top-level nav ----
add("Games", "Partidas", "Spiele", "Parties", "Spellen", "Partite")
add("Players", "Jugadores", "Spieler", "Joueurs", "Spelers", "Giocatori")
add("Scores", "Marcadores", "Spielstände", "Scores", "Uitslagen", "Punteggi")
add("Standings", "Clasificación", "Tabelle", "Classement", "Stand", "Classifica")
add("Settings", "Ajustes", "Einstellungen", "Réglages", "Instellingen", "Impostazioni")

# ---- Common buttons / words ----
add("Add", "Añadir", "Hinzufügen", "Ajouter", "Toevoegen", "Aggiungi")
add("Cancel", "Cancelar", "Abbrechen", "Annuler", "Annuleren", "Annulla")
add("Done", "Listo", "Fertig", "Terminé", "Klaar", "Fatto")
add("Continue", "Continuar", "Weiter", "Continuer", "Doorgaan", "Continua")
add("Close", "Cerrar", "Schließen", "Fermer", "Sluiten", "Chiudi")
add("Create", "Crear", "Erstellen", "Créer", "Aanmaken", "Crea")
add("Remove", "Quitar", "Entfernen", "Retirer", "Verwijderen", "Rimuovi")
add("Switch", "Cambiar", "Wechseln", "Changer", "Wisselen", "Cambia")
add("Back", "Atrás", "Zurück", "Retour", "Terug", "Indietro")
add("Next", "Siguiente", "Weiter", "Suivant", "Volgende", "Avanti")
add("Finish", "Finalizar", "Abschließen", "Terminer", "Voltooien", "Fine")
add("Exit", "Salir", "Beenden", "Quitter", "Afsluiten", "Esci")
add("Later", "Más tarde", "Später", "Plus tard", "Later", "Più tardi")
add("Declare", "Declarar", "Festlegen", "Déclarer", "Bevestigen", "Dichiara")
add("Search", "Buscar", "Suchen", "Rechercher", "Zoeken", "Cerca")
add("Filter", "Filtrar", "Filter", "Filtrer", "Filteren", "Filtra")
add("Sort", "Ordenar", "Sortieren", "Trier", "Sorteren", "Ordina")
add("Show", "Mostrar", "Anzeigen", "Afficher", "Tonen", "Mostra")
add("Group", "Grupo", "Gruppe", "Groupe", "Groep", "Gruppo")
add("Team", "Equipo", "Mannschaft", "Équipe", "Team", "Squadra")
add("League", "Liga", "Liga", "Ligue", "Competitie", "Lega")
add("Leagues", "Ligas", "Ligen", "Ligues", "Competities", "Leghe")
add("Game", "Partida", "Spiel", "Partie", "Spel", "Partita")
add("Plan", "Plan", "Tarif", "Forfait", "Abonnement", "Piano")
add("App", "App", "App", "App", "App", "App")
add("Version", "Versión", "Version", "Version", "Versie", "Versione")
add("Status", "Estado", "Status", "Statut", "Status", "Stato")
add("Result", "Resultado", "Ergebnis", "Résultat", "Resultaat", "Risultato")
add("Subscribe", "Suscribirse", "Abonnieren", "S’abonner", "Abonneren", "Abbonati")
add("Upgrade", "Mejorar plan", "Upgrade", "Améliorer", "Upgraden", "Esegui upgrade")
add("From", "Desde", "Von", "Du", "Van", "Da")
add("To", "Hasta", "Bis", "Au", "Tot", "A")
add("Home", "Local", "Heim", "Domicile", "Thuis", "Casa")
add("Away", "Visitante", "Auswärts", "Extérieur", "Uit", "Trasferta")
add("All", "Todos", "Alle", "Tous", "Alle", "Tutte")
add("Kick-off", "Hora", "Anstoß", "Coup d’envoi", "Aftrap", "Inizio")
add("Matchday", "Jornada", "Spieltag", "Journée", "Speeldag", "Giornata")
add("Deadline", "Fecha límite", "Frist", "Échéance", "Deadline", "Scadenza")
add("Filters", "Filtros", "Filter", "Filtres", "Filters", "Filtri")
add("Date range", "Rango de fechas", "Zeitraum", "Plage de dates", "Datumbereik", "Intervallo di date")
add("Welcome", "Bienvenido", "Willkommen", "Bienvenue", "Welkom", "Benvenuto")

# ---- Standings table abbreviations (Played/Won/Drawn/Lost) ----
add("P", "PJ", "Sp", "J", "G", "G")
add("W", "G", "S", "V", "W", "V")
add("D", "E", "U", "N", "GL", "N")
add("L", "P", "N", "D", "V", "P")
add("MD %lld", "J %lld", "ST %lld", "J %lld", "SD %lld", "G %lld")
add("Updated %@", "Actualizado %@", "Aktualisiert %@", "Mis à jour %@", "Bijgewerkt %@", "Aggiornato %@")

# ---- Loading / errors / empty states ----
add("Loading fixtures…", "Cargando partidos…", "Spiele werden geladen…", "Chargement des matchs…", "Wedstrijden laden…", "Caricamento partite…")
add("Loading scores…", "Cargando marcadores…", "Spielstände werden geladen…", "Chargement des scores…", "Uitslagen laden…", "Caricamento punteggi…")
add("Loading standings…", "Cargando clasificación…", "Tabelle wird geladen…", "Chargement du classement…", "Stand laden…", "Caricamento classifica…")
add("Loading teams…", "Cargando equipos…", "Mannschaften werden geladen…", "Chargement des équipes…", "Teams laden…", "Caricamento squadre…")
add("Rendering card…", "Generando tarjeta…", "Karte wird erstellt…", "Création de la carte…", "Kaart maken…", "Creazione scheda…")
add("Couldn't build card", "No se pudo crear la tarjeta", "Karte konnte nicht erstellt werden", "Impossible de créer la carte", "Kaart maken mislukt", "Impossibile creare la scheda")
add("Couldn't load fixtures", "No se pudieron cargar los partidos", "Spiele konnten nicht geladen werden", "Impossible de charger les matchs", "Wedstrijden laden mislukt", "Impossibile caricare le partite")
add("Couldn't load scores", "No se pudieron cargar los marcadores", "Spielstände konnten nicht geladen werden", "Impossible de charger les scores", "Uitslagen laden mislukt", "Impossibile caricare i punteggi")
add("Couldn't load standings", "No se pudo cargar la clasificación", "Tabelle konnte nicht geladen werden", "Impossible de charger le classement", "Stand laden mislukt", "Impossibile caricare la classifica")
add("Couldn't load teams", "No se pudieron cargar los equipos", "Mannschaften konnten nicht geladen werden", "Impossible de charger les équipes", "Teams laden mislukt", "Impossibile caricare le squadre")
add("Couldn't read file: %@", "No se pudo leer el archivo: %@", "Datei konnte nicht gelesen werden: %@", "Impossible de lire le fichier : %@", "Bestand lezen mislukt: %@", "Impossibile leggere il file: %@")
add("Import failed: %@", "Error al importar: %@", "Import fehlgeschlagen: %@", "Échec de l’import : %@", "Importeren mislukt: %@", "Importazione non riuscita: %@")
add("The card image could not be generated.", "No se pudo generar la imagen de la tarjeta.", "Das Kartenbild konnte nicht erstellt werden.", "L’image de la carte n’a pas pu être générée.", "De kaartafbeelding kon niet worden gemaakt.", "Impossibile generare l’immagine della scheda.")
add("No active players", "Sin jugadores activos", "Keine aktiven Spieler", "Aucun joueur actif", "Geen actieve spelers", "Nessun giocatore attivo")
add("No fixtures", "Sin partidos", "Keine Spiele", "Aucun match", "Geen wedstrijden", "Nessuna partita")
add("No fixtures available right now.", "No hay partidos disponibles ahora mismo.", "Derzeit sind keine Spiele verfügbar.", "Aucun match disponible pour le moment.", "Op dit moment geen wedstrijden beschikbaar.", "Nessuna partita disponibile al momento.")
add("No fixtures match your search.", "Ningún partido coincide con tu búsqueda.", "Keine Spiele entsprechen deiner Suche.", "Aucun match ne correspond à ta recherche.", "Geen wedstrijden komen overeen met je zoekopdracht.", "Nessuna partita corrisponde alla ricerca.")
add("No fixtures match these filters.", "Ningún partido coincide con estos filtros.", "Keine Spiele entsprechen diesen Filtern.", "Aucun match ne correspond à ces filtres.", "Geen wedstrijden komen overeen met deze filters.", "Nessuna partita corrisponde a questi filtri.")
add("No fixtures in this round.", "No hay partidos en esta ronda.", "Keine Spiele in dieser Runde.", "Aucun match dans cette manche.", "Geen wedstrijden in deze ronde.", "Nessuna partita in questo turno.")
add("No games yet", "Aún no hay partidas", "Noch keine Spiele", "Aucune partie pour l’instant", "Nog geen spellen", "Ancora nessuna partita")
add("Create your first Last Man Standing game.", "Crea tu primera partida de Last Man Standing.", "Erstelle dein erstes Last-Man-Standing-Spiel.", "Crée ta première partie de Last Man Standing.", "Maak je eerste Last Man Standing-spel.", "Crea la tua prima partita di Last Man Standing.")
add("No groups yet — create one on the Players screen.", "Aún no hay grupos: crea uno en la pantalla Jugadores.", "Noch keine Gruppen – erstelle eine im Bereich „Spieler“.", "Aucun groupe pour l’instant — créez-en un dans l’écran Joueurs.", "Nog geen groepen — maak er een op het scherm Spelers.", "Ancora nessun gruppo: creane uno nella schermata Giocatori.")
add("No picks recorded for this round.", "No hay selecciones registradas en esta ronda.", "Für diese Runde sind keine Tipps erfasst.", "Aucun choix enregistré pour cette manche.", "Geen keuzes vastgelegd voor deze ronde.", "Nessuna scelta registrata per questo turno.")
add("No players match.", "Ningún jugador coincide.", "Keine Spieler gefunden.", "Aucun joueur correspondant.", "Geen spelers gevonden.", "Nessun giocatore corrisponde.")
add("No players yet.", "Aún no hay jugadores.", "Noch keine Spieler.", "Aucun joueur pour l’instant.", "Nog geen spelers.", "Ancora nessun giocatore.")
add("No saved players yet. Add people here, then add them to a game.", "Aún no hay jugadores guardados. Añade personas aquí y luego agrégalas a una partida.", "Noch keine gespeicherten Spieler. Füge hier Personen hinzu und dann zu einem Spiel.", "Aucun joueur enregistré. Ajoute des personnes ici, puis ajoute-les à une partie.", "Nog geen opgeslagen spelers. Voeg hier mensen toe en daarna aan een spel.", "Ancora nessun giocatore salvato. Aggiungi persone qui e poi a una partita.")
add("No saved players yet. Add people on the Players tab first, then add them here.", "Aún no hay jugadores guardados. Añádelos primero en la pestaña Jugadores y luego aquí.", "Noch keine gespeicherten Spieler. Füge sie zuerst im Tab „Spieler“ hinzu und dann hier.", "Aucun joueur enregistré. Ajoute-les d’abord dans l’onglet Joueurs, puis ici.", "Nog geen opgeslagen spelers. Voeg ze eerst toe op het tabblad Spelers en daarna hier.", "Ancora nessun giocatore salvato. Aggiungili prima nella scheda Giocatori e poi qui.")

# ---- Games list / detail ----
add("Guided Setup", "Configuración guiada", "Geführte Einrichtung", "Configuration guidée", "Begeleide setup", "Configurazione guidata")
add("New Game", "Nueva partida", "Neues Spiel", "Nouvelle partie", "Nieuw spel", "Nuova partita")
add("Round %lld", "Ronda %lld", "Runde %lld", "Manche %lld", "Ronde %lld", "Turno %lld")
add("%lld active", "%lld activos", "%lld aktiv", "%lld actifs", "%lld actief", "%lld attivi")
add("Setup", "Preparación", "Vorbereitung", "Préparation", "Voorbereiding", "Preparazione")
add("Active", "Activa", "Aktiv", "En cours", "Actief", "In corso")
add("Complete", "Finalizada", "Beendet", "Terminée", "Voltooid", "Conclusa")
add("This Round", "Esta ronda", "Diese Runde", "Cette manche", "Deze ronde", "Questo turno")
add("Winner", "Ganador", "Gewinner", "Vainqueur", "Winnaar", "Vincitore")
add("Winners", "Ganadores", "Gewinner", "Vainqueurs", "Winnaars", "Vincitori")
add("Players (%lld)", "Jugadores (%lld)", "Spieler (%lld)", "Joueurs (%lld)", "Spelers (%lld)", "Giocatori (%lld)")
add("Add Players", "Añadir jugadores", "Spieler hinzufügen", "Ajouter des joueurs", "Spelers toevoegen", "Aggiungi giocatori")
add("Enter Picks", "Introducir selecciones", "Tipps eingeben", "Saisir les choix", "Keuzes invoeren", "Inserisci scelte")
add("Enter Results / Close", "Introducir resultados / Cerrar", "Ergebnisse eingeben / Schließen", "Saisir les résultats / Clôturer", "Resultaten invoeren / Sluiten", "Inserisci risultati / Chiudi")
add("Open Round", "Abrir ronda", "Runde öffnen", "Ouvrir une manche", "Ronde openen", "Apri turno")
add("Resolve Round", "Resolver ronda", "Runde auflösen", "Résoudre la manche", "Ronde oplossen", "Risolvi turno")
add("Manually declare winner(s)", "Declarar ganador(es) manualmente", "Gewinner manuell festlegen", "Déclarer le(s) vainqueur(s) manuellement", "Winnaar(s) handmatig bepalen", "Dichiara vincitore/i manualmente")
add("Declare Winner(s)…", "Declarar ganador(es)…", "Gewinner festlegen…", "Déclarer le(s) vainqueur(s)…", "Winnaar(s) bepalen…", "Dichiara vincitore/i…")
add("Declare Winner(s)", "Declarar ganador(es)", "Gewinner festlegen", "Déclarer le(s) vainqueur(s)", "Winnaar(s) bepalen", "Dichiara vincitore/i")
add("Share Fixtures Card", "Compartir tarjeta de partidos", "Spielplan-Karte teilen", "Partager la carte des matchs", "Wedstrijdkaart delen", "Condividi scheda partite")
add("Share Picks Card", "Compartir tarjeta de selecciones", "Tipp-Karte teilen", "Partager la carte des choix", "Keuzekaart delen", "Condividi scheda scelte")
add("Share Results Card", "Compartir tarjeta de resultados", "Ergebnis-Karte teilen", "Partager la carte des résultats", "Resultatenkaart delen", "Condividi scheda risultati")
add("Share %@ Card", "Compartir tarjeta de %@", "%@-Karte teilen", "Partager la carte %@", "%@-kaart delen", "Condividi scheda %@")
add("Remove %@", "Quitar a %@", "%@ entfernen", "Retirer %@", "%@ verwijderen", "Rimuovi %@")
add("Remove %@?", "¿Quitar a %@?", "%@ entfernen?", "Retirer %@ ?", "%@ verwijderen?", "Rimuovere %@?")
add("%@ is removed from the game and their picks deleted. This can't be undone.",
    "%@ se quita de la partida y se eliminan sus selecciones. Esto no se puede deshacer.",
    "%@ wird aus dem Spiel entfernt und die Tipps werden gelöscht. Das kann nicht rückgängig gemacht werden.",
    "%@ est retiré de la partie et ses choix sont supprimés. Cette action est irréversible.",
    "%@ wordt uit het spel verwijderd en hun keuzes worden gewist. Dit kan niet ongedaan worden gemaakt.",
    "%@ viene rimosso dalla partita e le sue scelte vengono eliminate. Operazione irreversibile.")

# ---- New Game ----
add("Game name", "Nombre de la partida", "Spielname", "Nom de la partie", "Spelnaam", "Nome partita")
add("Summaries", "Resúmenes", "Zusammenfassungen", "Récapitulatifs", "Samenvattingen", "Riepiloghi")
add("Anonymity", "Anonimato", "Anonymität", "Anonymat", "Anonimiteit", "Anonimato")
add("Anonymous", "Anónimo", "Anonym", "Anonyme", "Anoniem", "Anonimo")
add("Named", "Con nombres", "Mit Namen", "Avec noms", "Met namen", "Con nomi")
add("Pick one league, or blend several — players can then pick teams from any of them.",
    "Elige una liga o combina varias: los jugadores podrán elegir equipos de cualquiera de ellas.",
    "Wähle eine Liga oder kombiniere mehrere – Spieler können dann Mannschaften aus jeder davon wählen.",
    "Choisis une ligue ou combine-en plusieurs : les joueurs pourront choisir des équipes dans chacune.",
    "Kies één competitie of combineer er meerdere — spelers kunnen dan teams uit elk ervan kiezen.",
    "Scegli una lega o combinane più di una: i giocatori potranno scegliere squadre da ognuna.")
add("%@ (you)", "%@ (tú)", "%@ (du)", "%@ (toi)", "%@ (jij)", "%@ (tu)")
add("You're playing in this game — your pick shows on shared cards (⚑).",
    "Juegas en esta partida: tu selección aparece en las tarjetas compartidas (⚑).",
    "Du spielst in diesem Spiel mit – dein Tipp erscheint auf geteilten Karten (⚑).",
    "Tu joues dans cette partie — ton choix apparaît sur les cartes partagées (⚑).",
    "Je speelt mee in dit spel — je keuze staat op gedeelde kaarten (⚑).",
    "Giochi in questa partita: la tua scelta appare sulle schede condivise (⚑).")
add("You're running this game but not playing — no ⚑ on cards.",
    "Diriges esta partida pero no juegas: sin ⚑ en las tarjetas.",
    "Du leitest dieses Spiel, spielst aber nicht mit – kein ⚑ auf den Karten.",
    "Tu organises cette partie sans y jouer — pas de ⚑ sur les cartes.",
    "Je beheert dit spel maar speelt niet mee — geen ⚑ op kaarten.",
    "Gestisci questa partita ma non giochi: nessuna ⚑ sulle schede.")

# ---- Add Players ----
add("You're playing — your pick shows on shared cards (⚑).",
    "Juegas: tu selección aparece en las tarjetas compartidas (⚑).",
    "Du spielst mit – dein Tipp erscheint auf geteilten Karten (⚑).",
    "Tu joues — ton choix apparaît sur les cartes partagées (⚑).",
    "Je speelt mee — je keuze staat op gedeelde kaarten (⚑).",
    "Giochi: la tua scelta appare sulle schede condivise (⚑).")
add("You're not playing this game — no ⚑ on cards.",
    "No juegas esta partida: sin ⚑ en las tarjetas.",
    "Du spielst dieses Spiel nicht mit – kein ⚑ auf den Karten.",
    "Tu ne joues pas à cette partie — pas de ⚑ sur les cartes.",
    "Je speelt dit spel niet mee — geen ⚑ op kaarten.",
    "Non giochi questa partita: nessuna ⚑ sulle schede.")
add("All players", "Todos los jugadores", "Alle Spieler", "Tous les joueurs", "Alle spelers", "Tutti i giocatori")
add("Add from your players", "Añadir desde tus jugadores", "Aus deinen Spielern hinzufügen", "Ajouter depuis tes joueurs", "Toevoegen uit je spelers", "Aggiungi dai tuoi giocatori")
add("Add all (%lld)", "Añadir todos (%lld)", "Alle hinzufügen (%lld)", "Tout ajouter (%lld)", "Alles toevoegen (%lld)", "Aggiungi tutti (%lld)")
add("Everyone in your roster is already in this game.", "Todas tus personas ya están en esta partida.", "Alle aus deiner Liste sind bereits in diesem Spiel.", "Tout le monde de ta liste est déjà dans cette partie.", "Iedereen op je lijst zit al in dit spel.", "Tutti nel tuo elenco sono già in questa partita.")
add("Everyone in this group is already in this game.", "Todo el grupo ya está en esta partida.", "Alle dieser Gruppe sind bereits in diesem Spiel.", "Tout ce groupe est déjà dans cette partie.", "Iedereen in deze groep zit al in dit spel.", "Tutto il gruppo è già in questa partita.")
add("In this game (%lld)", "En esta partida (%lld)", "In diesem Spiel (%lld)", "Dans cette partie (%lld)", "In dit spel (%lld)", "In questa partita (%lld)")
add("Search players", "Buscar jugadores", "Spieler suchen", "Rechercher des joueurs", "Spelers zoeken", "Cerca giocatori")

# ---- Players tab ----
add("Add a player", "Añadir un jugador", "Spieler hinzufügen", "Ajouter un joueur", "Een speler toevoegen", "Aggiungi un giocatore")
add("Player name", "Nombre del jugador", "Spielername", "Nom du joueur", "Spelersnaam", "Nome giocatore")
add("‘%@’ is already in your players.", "«%@» ya está en tus jugadores.", "„%@“ ist bereits in deinen Spielern.", "« %@ » est déjà dans tes joueurs.", "‘%@’ staat al in je spelers.", "«%@» è già tra i tuoi giocatori.")
add("Import", "Importar", "Importieren", "Importer", "Importeren", "Importa")
add("Import CSV", "Importar CSV", "CSV importieren", "Importer un CSV", "CSV importeren", "Importa CSV")
add("Import into group", "Importar al grupo", "In Gruppe importieren", "Importer dans le groupe", "Importeren in groep", "Importa nel gruppo")
add("No group", "Sin grupo", "Keine Gruppe", "Aucun groupe", "Geen groep", "Nessun gruppo")
add("One name per row. Add a group with `Name, Group`. Rows without one go to the selected import group above. `Name, Email` still works (email ignored).",
    "Un nombre por fila. Añade un grupo con «Nombre, Grupo». Las filas sin grupo van al grupo de importación seleccionado arriba. «Nombre, Email» también funciona (el email se ignora).",
    "Ein Name pro Zeile. Gruppe mit „Name, Gruppe“ angeben. Zeilen ohne Gruppe kommen in die oben gewählte Import-Gruppe. „Name, E-Mail“ funktioniert weiterhin (E-Mail wird ignoriert).",
    "Un nom par ligne. Ajoute un groupe avec « Nom, Groupe ». Les lignes sans groupe vont dans le groupe d’import sélectionné ci-dessus. « Nom, E-mail » fonctionne aussi (e-mail ignoré).",
    "Eén naam per regel. Voeg een groep toe met ‘Naam, Groep’. Regels zonder groep gaan naar de hierboven gekozen importgroep. ‘Naam, E-mail’ werkt nog steeds (e-mail genegeerd).",
    "Un nome per riga. Aggiungi un gruppo con «Nome, Gruppo». Le righe senza gruppo vanno nel gruppo di importazione selezionato sopra. «Nome, Email» funziona ancora (email ignorata).")
add("Groups", "Grupos", "Gruppen", "Groupes", "Groepen", "Gruppi")
add("Groups (%lld)", "Grupos (%lld)", "Gruppen (%lld)", "Groupes (%lld)", "Groepen (%lld)", "Gruppi (%lld)")
add("New group name", "Nombre del nuevo grupo", "Name der neuen Gruppe", "Nom du nouveau groupe", "Naam nieuwe groep", "Nome nuovo gruppo")
add("Your players (%lld)", "Tus jugadores (%lld)", "Deine Spieler (%lld)", "Tes joueurs (%lld)", "Jouw spelers (%lld)", "I tuoi giocatori (%lld)")
add("Imported 1 new player", "Importado 1 jugador nuevo", "1 neuer Spieler importiert", "1 nouveau joueur importé", "1 nieuwe speler geïmporteerd", "1 nuovo giocatore importato")
add("Imported %lld new players", "Importados %lld jugadores nuevos", "%lld neue Spieler importiert", "%lld nouveaux joueurs importés", "%lld nieuwe spelers geïmporteerd", "%lld nuovi giocatori importati")
add("1 already existed", "1 ya existía", "1 bereits vorhanden", "1 existait déjà", "1 bestond al", "1 già presente")
add("%lld already existed", "%lld ya existían", "%lld bereits vorhanden", "%lld existaient déjà", "%lld bestonden al", "%lld già presenti")
add("1 group assignment", "1 asignación de grupo", "1 Gruppenzuordnung", "1 affectation de groupe", "1 groepstoewijzing", "1 assegnazione di gruppo")
add("%lld group assignments", "%lld asignaciones de grupo", "%lld Gruppenzuordnungen", "%lld affectations de groupe", "%lld groepstoewijzingen", "%lld assegnazioni di gruppo")

# ---- Member groups ----
# (Groups header reused above)

# ---- Open Round ----
add("Open %@ %lld", "Abrir %@ %lld", "%@ %lld öffnen", "Ouvrir %@ %lld", "%@ %lld openen", "Apri %@ %lld")
add("Round", "Ronda", "Runde", "Manche", "Ronde", "Turno")
add("Playoff Round", "Ronda de desempate", "Playoff-Runde", "Manche de barrage", "Play-offronde", "Turno di spareggio")
add("Rollover Round", "Ronda de repetición", "Wiederholungsrunde", "Manche rejouée", "Doorrolronde", "Turno di riporto")
add("All leagues", "Todas las ligas", "Alle Ligen", "Toutes les ligues", "Alle competities", "Tutte le leghe")
add("Unplayed only", "Solo no jugados", "Nur ungespielte", "Non joués uniquement", "Alleen ongespeeld", "Solo non giocate")
add("Filter by date", "Filtrar por fecha", "Nach Datum filtern", "Filtrer par date", "Filteren op datum", "Filtra per data")
add("Fixtures (%lld selected)", "Partidos (%lld seleccionados)", "Spiele (%lld ausgewählt)", "Matchs (%lld sélectionnés)", "Wedstrijden (%lld geselecteerd)", "Partite (%lld selezionate)")
add("Select all", "Seleccionar todo", "Alle auswählen", "Tout sélectionner", "Alles selecteren", "Seleziona tutto")
add("Deselect all", "Deseleccionar todo", "Alle abwählen", "Tout désélectionner", "Alles deselecteren", "Deseleziona tutto")
add("Picks due by", "Selecciones antes de", "Tipps fällig bis", "Choix attendus avant", "Keuzes vóór", "Scelte entro")
add("Defaults to 24 hours before the first selected kick-off. A guide for the manager — picks aren't locked automatically.",
    "Por defecto, 24 horas antes del primer partido seleccionado. Es una guía para el organizador: las selecciones no se bloquean automáticamente.",
    "Standardmäßig 24 Stunden vor dem ersten ausgewählten Anstoß. Nur ein Hinweis für den Organisator – Tipps werden nicht automatisch gesperrt.",
    "Par défaut, 24 heures avant le premier coup d’envoi sélectionné. Un repère pour l’organisateur — les choix ne sont pas verrouillés automatiquement.",
    "Standaard 24 uur vóór de eerste geselecteerde aftrap. Een richtlijn voor de beheerder — keuzes worden niet automatisch vergrendeld.",
    "Per impostazione predefinita, 24 ore prima del primo calcio d’inizio selezionato. Un riferimento per l’organizzatore: le scelte non si bloccano automaticamente.")

# ---- Picks entry ----
add("Picks · Round %lld", "Selecciones · Ronda %lld", "Tipps · Runde %lld", "Choix · Manche %lld", "Keuzes · Ronde %lld", "Scelte · Turno %lld")
add("Auto-Assign", "Asignar automáticamente", "Automatisch zuweisen", "Attribuer auto", "Automatisch toewijzen", "Assegna automaticamente")
add("All (%lld)", "Todos (%lld)", "Alle (%lld)", "Tous (%lld)", "Alle (%lld)", "Tutti (%lld)")
add("Unassigned (%lld)", "Sin asignar (%lld)", "Nicht zugewiesen (%lld)", "Non attribués (%lld)", "Niet toegewezen (%lld)", "Non assegnati (%lld)")
add("Everyone's assigned.", "Todos están asignados.", "Alle sind zugewiesen.", "Tout le monde est attribué.", "Iedereen is toegewezen.", "Tutti sono assegnati.")
add("Assign", "Asignar", "Zuweisen", "Attribuer", "Toewijzen", "Assegna")
add("Clear pick", "Borrar selección", "Tipp löschen", "Effacer le choix", "Keuze wissen", "Cancella scelta")
add("Auto-assign 1 player?", "¿Asignar automáticamente a 1 jugador?", "1 Spieler automatisch zuweisen?", "Attribuer automatiquement à 1 joueur ?", "1 speler automatisch toewijzen?", "Assegnare automaticamente a 1 giocatore?")
add("Auto-assign %lld players?", "¿Asignar automáticamente a %lld jugadores?", "%lld Spieler automatisch zuweisen?", "Attribuer automatiquement à %lld joueurs ?", "%lld spelers automatisch toewijzen?", "Assegnare automaticamente a %lld giocatori?")
add("Each unassigned player gets the bottom-of-table team still available to them.",
    "Cada jugador sin asignar recibe el equipo más bajo de la tabla que aún tenga disponible.",
    "Jeder nicht zugewiesene Spieler erhält die in der Tabelle am tiefsten stehende, noch verfügbare Mannschaft.",
    "Chaque joueur non attribué reçoit l’équipe la plus basse au classement encore disponible pour lui.",
    "Elke niet-toegewezen speler krijgt het laagst geklasseerde team dat nog beschikbaar is.",
    "Ogni giocatore non assegnato riceve la squadra più in basso in classifica ancora disponibile.")

# ---- Results entry ----
add("Results · Round %lld", "Resultados · Ronda %lld", "Ergebnisse · Runde %lld", "Résultats · Manche %lld", "Resultaten · Ronde %lld", "Risultati · Turno %lld")
add("Pull results from server", "Obtener resultados del servidor", "Ergebnisse vom Server laden", "Récupérer les résultats du serveur", "Resultaten van server ophalen", "Scarica risultati dal server")
add("Close Round", "Cerrar ronda", "Runde schließen", "Clôturer la manche", "Ronde sluiten", "Chiudi turno")
add("Home Win", "Victoria local", "Heimsieg", "Victoire à domicile", "Thuiszege", "Vittoria casa")
add("Away Win", "Victoria visitante", "Auswärtssieg", "Victoire à l’extérieur", "Uitzege", "Vittoria trasferta")
add("Draw", "Empate", "Unentschieden", "Match nul", "Gelijkspel", "Pareggio")
add("Postponed", "Aplazado", "Verschoben", "Reporté", "Uitgesteld", "Rinviata")

# ---- Declare winners ----
add("Select the winner(s)", "Selecciona al ganador(es)", "Gewinner auswählen", "Sélectionne le(s) vainqueur(s)", "Selecteer de winnaar(s)", "Seleziona il/i vincitore/i")
add("Selected players win; everyone else is eliminated and the game ends.",
    "Los jugadores seleccionados ganan; el resto queda eliminado y la partida termina.",
    "Die ausgewählten Spieler gewinnen; alle anderen scheiden aus und das Spiel endet.",
    "Les joueurs sélectionnés gagnent ; tous les autres sont éliminés et la partie se termine.",
    "De geselecteerde spelers winnen; de rest valt af en het spel eindigt.",
    "I giocatori selezionati vincono; tutti gli altri sono eliminati e la partita finisce.")
add("Eliminated", "Eliminado", "Ausgeschieden", "Éliminé", "Afgevallen", "Eliminato")

# ---- Tie resolution ----
add("No Clear Winner", "Sin ganador claro", "Kein klarer Sieger", "Pas de vainqueur net", "Geen duidelijke winnaar", "Nessun vincitore netto")
add("Everyone still in was eliminated this round — no clear winner. How should it resolve?",
    "Todos los que seguían en juego quedaron eliminados esta ronda: no hay ganador claro. ¿Cómo se resuelve?",
    "Alle noch verbliebenen Spieler sind in dieser Runde ausgeschieden – kein klarer Sieger. Wie soll es aufgelöst werden?",
    "Tous les joueurs encore en lice ont été éliminés cette manche — pas de vainqueur net. Comment résoudre ?",
    "Iedereen die nog meedeed, viel deze ronde af — geen duidelijke winnaar. Hoe los je dit op?",
    "Tutti i giocatori ancora in gioco sono stati eliminati in questo turno: nessun vincitore netto. Come si risolve?")
add("Split the win", "Repartir la victoria", "Sieg teilen", "Partager la victoire", "Winst delen", "Dividi la vittoria")
add("Joint winners — the prize is divided.", "Ganadores conjuntos: el premio se reparte.", "Gemeinsame Gewinner – der Preis wird geteilt.", "Vainqueurs ex æquo — le prix est partagé.", "Gedeelde winnaars — de prijs wordt verdeeld.", "Vincitori a pari merito: il premio viene diviso.")
add("Roll the week", "Repetir la jornada", "Woche wiederholen", "Rejouer la semaine", "Week opnieuw", "Ripeti la giornata")
add("The %lld tied players carry forward and replay.", "Los %lld jugadores empatados continúan y vuelven a jugar.", "Die %lld punktgleichen Spieler kommen weiter und spielen erneut.", "Les %lld joueurs à égalité poursuivent et rejouent.", "De %lld gelijke spelers gaan door en spelen opnieuw.", "I %lld giocatori a pari merito proseguono e rigiocano.")
add("Their team pool resets — all teams open again.", "Su grupo de equipos se reinicia: todos los equipos vuelven a estar disponibles.", "Ihr Mannschafts-Pool wird zurückgesetzt – alle Mannschaften sind wieder verfügbar.", "Leur réserve d’équipes est réinitialisée — toutes les équipes redeviennent disponibles.", "Hun teampool wordt gereset — alle teams zijn weer beschikbaar.", "Il loro insieme di squadre si azzera: tutte le squadre tornano disponibili.")
add("Everyone back in", "Todos vuelven", "Alle wieder rein", "Tout le monde revient", "Iedereen terug", "Tutti di nuovo in gioco")
add("All %lld players reinstated, picks reset.", "Los %lld jugadores readmitidos, selecciones reiniciadas.", "Alle %lld Spieler wieder dabei, Tipps zurückgesetzt.", "Les %lld joueurs réintégrés, choix réinitialisés.", "Alle %lld spelers teruggeplaatst, keuzes gereset.", "Tutti i %lld giocatori reintegrati, scelte azzerate.")

# ---- Scores search ----
add("Search team", "Buscar equipo", "Mannschaft suchen", "Rechercher une équipe", "Team zoeken", "Cerca squadra")
add("Clear all", "Borrar todo", "Alles löschen", "Tout effacer", "Alles wissen", "Cancella tutto")

# ---- Wizard steps ----
add("Step %lld of %lld", "Paso %lld de %lld", "Schritt %lld von %lld", "Étape %lld sur %lld", "Stap %lld van %lld", "Passo %lld di %lld")
add("Set up your players", "Configura tus jugadores", "Richte deine Spieler ein", "Configure tes joueurs", "Stel je spelers in", "Configura i tuoi giocatori")
add("Add the people who'll play, and optionally group them (e.g. \"Office\"). This is your reusable roster.",
    "Añade a las personas que jugarán y, opcionalmente, agrúpalas (p. ej. «Oficina»). Esta es tu lista reutilizable.",
    "Füge die Personen hinzu, die mitspielen, und gruppiere sie optional (z. B. „Büro“). Das ist deine wiederverwendbare Liste.",
    "Ajoute les personnes qui joueront et, si tu veux, regroupe-les (p. ex. « Bureau »). C’est ta liste réutilisable.",
    "Voeg de mensen toe die meespelen en groepeer ze eventueel (bijv. ‘Kantoor’). Dit is je herbruikbare lijst.",
    "Aggiungi le persone che giocheranno e, se vuoi, raggruppale (es. «Ufficio»). Questo è il tuo elenco riutilizzabile.")
add("Open Players", "Abrir Jugadores", "Spieler öffnen", "Ouvrir Joueurs", "Spelers openen", "Apri Giocatori")
add("Create the game", "Crea la partida", "Spiel erstellen", "Crée la partie", "Maak het spel", "Crea la partita")
add("Name it, choose whether you're playing, and set anonymity for shared cards.",
    "Ponle nombre, elige si juegas y configura el anonimato de las tarjetas compartidas.",
    "Gib ihm einen Namen, wähle, ob du mitspielst, und lege die Anonymität für geteilte Karten fest.",
    "Donne-lui un nom, choisis si tu joues, et règle l’anonymat des cartes partagées.",
    "Geef het een naam, kies of je meespeelt en stel anonimiteit in voor gedeelde kaarten.",
    "Dagli un nome, scegli se giochi e imposta l’anonimato per le schede condivise.")
add("Add players to the game", "Añade jugadores a la partida", "Spieler zum Spiel hinzufügen", "Ajoute des joueurs à la partie", "Voeg spelers toe aan het spel", "Aggiungi giocatori alla partita")
add("Pull people from your roster into this game — you need at least two to play.", "Trae personas de tu lista a esta partida: necesitas al menos dos para jugar.", "Hol Personen aus deiner Liste in dieses Spiel – du brauchst mindestens zwei zum Spielen.", "Ajoute des personnes de ta liste à cette partie — il en faut au moins deux pour jouer.", "Haal mensen uit je lijst naar dit spel — je hebt er minstens twee nodig om te spelen.", "Porta persone dal tuo elenco in questa partita: ne servono almeno due per giocare.")
add("A game needs at least 2 players to start a round.", "Una partida necesita al menos 2 jugadores para empezar una ronda.", "Ein Spiel braucht mindestens 2 Spieler, um eine Runde zu starten.", "Une partie nécessite au moins 2 joueurs pour lancer une manche.", "Een spel heeft minstens 2 spelers nodig om een ronde te starten.", "Una partita richiede almeno 2 giocatori per iniziare un turno.")
add("Open round 1", "Abre la ronda 1", "Runde 1 öffnen", "Ouvre la manche 1", "Open ronde 1", "Apri il turno 1")
add("Pick the fixtures this round runs on and set the picks deadline.",
    "Elige los partidos de esta ronda y fija la fecha límite de selecciones.",
    "Wähle die Spiele dieser Runde und lege die Tipp-Frist fest.",
    "Choisis les matchs de cette manche et fixe l’échéance des choix.",
    "Kies de wedstrijden voor deze ronde en stel de keuzedeadline in.",
    "Scegli le partite di questo turno e imposta la scadenza delle scelte.")
add("Share the fixtures", "Comparte los partidos", "Spiele teilen", "Partage les matchs", "Deel de wedstrijden", "Condividi le partite")
add("Send the fixtures card so players know the matches to choose from.",
    "Envía la tarjeta de partidos para que los jugadores sepan entre qué partidos elegir.",
    "Sende die Spielplan-Karte, damit die Spieler wissen, aus welchen Spielen sie wählen können.",
    "Envoie la carte des matchs pour que les joueurs sachent parmi quels matchs choisir.",
    "Stuur de wedstrijdkaart zodat spelers weten uit welke wedstrijden ze kunnen kiezen.",
    "Invia la scheda partite così i giocatori sanno tra quali partite scegliere.")
add("Enter & assign picks", "Introduce y asigna selecciones", "Tipps eingeben & zuweisen", "Saisir et attribuer les choix", "Keuzes invoeren & toewijzen", "Inserisci e assegna le scelte")
add("Record each player's team, then Auto-Assign anyone who didn't reply in time.",
    "Registra el equipo de cada jugador y luego asigna automáticamente a quien no respondió a tiempo.",
    "Erfasse die Mannschaft jedes Spielers und weise allen, die nicht rechtzeitig geantwortet haben, automatisch eine zu.",
    "Note l’équipe de chaque joueur, puis attribue automatiquement à ceux qui n’ont pas répondu à temps.",
    "Leg het team van elke speler vast en wijs automatisch toe aan wie niet op tijd reageerde.",
    "Registra la squadra di ogni giocatore, poi assegna automaticamente a chi non ha risposto in tempo.")
add("Share the picks", "Comparte las selecciones", "Tipps teilen", "Partage les choix", "Deel de keuzes", "Condividi le scelte")
add("Send the picks summary so everyone sees who picked what.",
    "Envía el resumen de selecciones para que todos vean quién eligió qué.",
    "Sende die Tipp-Übersicht, damit alle sehen, wer was getippt hat.",
    "Envoie le récapitulatif des choix pour que chacun voie qui a choisi quoi.",
    "Stuur het keuzeoverzicht zodat iedereen ziet wie wat koos.",
    "Invia il riepilogo delle scelte così tutti vedono chi ha scelto cosa.")
add("Enter results & close", "Introduce resultados y cierra", "Ergebnisse eingeben & schließen", "Saisir les résultats et clôturer", "Resultaten invoeren & sluiten", "Inserisci risultati e chiudi")
add("Pull the results (or set them), then close the round to work out who's out.",
    "Obtén los resultados (o introdúcelos) y luego cierra la ronda para ver quién queda fuera.",
    "Lade die Ergebnisse (oder trage sie ein) und schließe dann die Runde, um zu sehen, wer ausscheidet.",
    "Récupère les résultats (ou saisis-les), puis clôture la manche pour voir qui est éliminé.",
    "Haal de resultaten op (of voer ze in) en sluit dan de ronde om te bepalen wie afvalt.",
    "Scarica i risultati (o inseriscili), poi chiudi il turno per vedere chi è fuori.")
add("Share the results", "Comparte los resultados", "Ergebnisse teilen", "Partage les résultats", "Deel de resultaten", "Condividi i risultati")
add("Send the results card — who survived to round 2. That's the loop! Carry on as normal from here.",
    "Envía la tarjeta de resultados: quién pasa a la ronda 2. ¡Ese es el ciclo! A partir de aquí, sigue como siempre.",
    "Sende die Ergebnis-Karte – wer in Runde 2 kommt. Das ist der Ablauf! Mach ab hier wie gewohnt weiter.",
    "Envoie la carte des résultats — qui passe en manche 2. C’est la boucle ! Continue normalement à partir d’ici.",
    "Stuur de resultatenkaart — wie door is naar ronde 2. Dat is de cyclus! Ga vanaf hier gewoon door.",
    "Invia la scheda risultati: chi passa al turno 2. Questo è il ciclo! Da qui prosegui come al solito.")
add("Open Players", "Abrir Jugadores", "Spieler öffnen", "Ouvrir Joueurs", "Spelers openen", "Apri Giocatori")
add("Share Fixtures Card", "Compartir tarjeta de partidos", "Spielplan-Karte teilen", "Partager la carte des matchs", "Wedstrijdkaart delen", "Condividi scheda partite")

# ---- Onboarding ----
add("What's your name? You'll be added to games you create, and your pick is always shown on shared summary cards — even in anonymous mode — so it's fair on the other players.",
    "¿Cómo te llamas? Te añadiremos a las partidas que crees y tu selección siempre aparecerá en las tarjetas de resumen compartidas —incluso en modo anónimo— para que sea justo con los demás jugadores.",
    "Wie heißt du? Du wirst zu den von dir erstellten Spielen hinzugefügt, und dein Tipp wird auf geteilten Übersichtskarten immer angezeigt – auch im anonymen Modus – damit es für die anderen Spieler fair ist.",
    "Comment t’appelles-tu ? Tu seras ajouté aux parties que tu crées, et ton choix apparaît toujours sur les cartes récapitulatives partagées — même en mode anonyme — pour rester équitable envers les autres joueurs.",
    "Wat is je naam? Je wordt toegevoegd aan spellen die je maakt, en je keuze staat altijd op gedeelde samenvattingskaarten — ook in anonieme modus — zodat het eerlijk is voor de andere spelers.",
    "Come ti chiami? Verrai aggiunto alle partite che crei e la tua scelta è sempre mostrata sulle schede riepilogative condivise — anche in modalità anonima — per essere equi verso gli altri giocatori.")
add("Your name", "Tu nombre", "Dein Name", "Ton nom", "Je naam", "Il tuo nome")
add("e.g. Andy", "p. ej. Andy", "z. B. Andy", "p. ex. Andy", "bijv. Andy", "es. Andy")

# ---- Settings ----
add("You", "Tú", "Du", "Toi", "Jij", "Tu")
add("you", "tú", "du", "toi", "jij", "tu")
add("Your name", "Tu nombre", "Dein Name", "Ton nom", "Je naam", "Il tuo nome")
add("You're added to games you create, and your pick is always shown on shared summary cards.",
    "Te añadimos a las partidas que creas, y tu selección siempre aparece en las tarjetas de resumen compartidas.",
    "Du wirst zu den von dir erstellten Spielen hinzugefügt, und dein Tipp erscheint immer auf geteilten Übersichtskarten.",
    "Tu es ajouté aux parties que tu crées, et ton choix apparaît toujours sur les cartes récapitulatives partagées.",
    "Je wordt toegevoegd aan spellen die je maakt, en je keuze staat altijd op gedeelde samenvattingskaarten.",
    "Vieni aggiunto alle partite che crei e la tua scelta appare sempre sulle schede riepilogative condivise.")
add("Subscription", "Suscripción", "Abo", "Abonnement", "Abonnement", "Abbonamento")
add("Restore Purchases", "Restaurar compras", "Käufe wiederherstellen", "Restaurer les achats", "Aankopen herstellen", "Ripristina acquisti")
add("Developer (testing)", "Desarrollador (pruebas)", "Entwickler (Test)", "Développeur (test)", "Ontwikkelaar (testen)", "Sviluppatore (test)")
add("Simulate tier", "Simular plan", "Stufe simulieren", "Simuler le niveau", "Niveau simuleren", "Simula livello")
add("Flips ad-on / ad-off + league allowance without a purchase. Free = 1 league; paid = all.",
    "Cambia con/sin anuncios y el número de ligas sin comprar. Gratis = 1 liga; de pago = todas.",
    "Schaltet Werbung an/aus und das Liga-Kontingent ohne Kauf um. Kostenlos = 1 Liga; bezahlt = alle.",
    "Active/désactive la pub et le quota de ligues sans achat. Gratuit = 1 ligue ; payant = toutes.",
    "Schakelt advertenties aan/uit en het competitietegoed zonder aankoop. Gratis = 1 competitie; betaald = alle.",
    "Attiva/disattiva la pubblicità e il numero di leghe senza acquisto. Gratis = 1 lega; a pagamento = tutte.")
add("Language", "Idioma", "Sprache", "Langue", "Taal", "Lingua")
add("System Default", "Predeterminado del sistema", "Systemstandard", "Par défaut du système", "Systeemstandaard", "Predefinito di sistema")
add("Choose the app's language. Team, player and league names always come from the league data.",
    "Elige el idioma de la app. Los nombres de equipos, jugadores y ligas siempre provienen de los datos de la liga.",
    "Wähle die Sprache der App. Mannschafts-, Spieler- und Liganamen stammen immer aus den Ligadaten.",
    "Choisis la langue de l’app. Les noms d’équipes, de joueurs et de ligues proviennent toujours des données de la ligue.",
    "Kies de taal van de app. Team-, speler- en competitienamen komen altijd uit de competitiegegevens.",
    "Scegli la lingua dell’app. I nomi di squadre, giocatori e leghe provengono sempre dai dati della lega.")
add("About", "Acerca de", "Über", "À propos", "Over", "Informazioni")
add("Not affiliated with, licensed by or endorsed by any football club, league or federation. An independent tool — team names and fixtures are factual data shown for reference only.",
    "No está afiliado, licenciado ni respaldado por ningún club, liga o federación de fútbol. Es una herramienta independiente: los nombres de equipos y los partidos son datos factuales mostrados solo como referencia.",
    "Nicht verbunden mit, lizenziert von oder unterstützt durch einen Fußballverein, eine Liga oder einen Verband. Ein unabhängiges Tool – Mannschaftsnamen und Spiele sind sachliche Daten, die nur zur Information angezeigt werden.",
    "Sans affiliation, licence ni approbation d’un club, d’une ligue ou d’une fédération de football. Outil indépendant — les noms d’équipes et les matchs sont des données factuelles affichées à titre d’information uniquement.",
    "Niet verbonden aan, gelicentieerd door of onderschreven door een voetbalclub, competitie of federatie. Een onafhankelijke tool — teamnamen en wedstrijden zijn feitelijke gegevens die alleen ter informatie worden getoond.",
    "Non affiliato, concesso in licenza o approvato da alcun club, lega o federazione calcistica. Strumento indipendente: i nomi delle squadre e le partite sono dati fattuali mostrati solo a scopo informativo.")
add("Disable %@?", "¿Desactivar %@?", "%@ deaktivieren?", "Désactiver %@ ?", "%@ uitschakelen?", "Disattivare %@?")
add("Delete games in %@?", "¿Eliminar partidas de %@?", "Spiele in %@ löschen?", "Supprimer les parties de %@ ?", "Spellen in %@ verwijderen?", "Eliminare le partite in %@?")
add("Switch to %@?", "¿Cambiar a %@?", "Zu %@ wechseln?", "Passer à %@ ?", "Wisselen naar %@?", "Passare a %@?")
add("Disable & delete", "Desactivar y eliminar", "Deaktivieren & löschen", "Désactiver et supprimer", "Uitschakelen en verwijderen", "Disattiva ed elimina")
add("Disabling %@ removes its data from this device.",
    "Desactivar %@ elimina sus datos de este dispositivo.",
    "Beim Deaktivieren von %@ werden dessen Daten von diesem Gerät entfernt.",
    "Désactiver %@ supprime ses données de cet appareil.",
    "%@ uitschakelen verwijdert de gegevens van dit apparaat.",
    "Disattivare %@ rimuove i suoi dati da questo dispositivo.")
add("Disabling %@ removes its data from this device and deletes 1 game that uses it.",
    "Desactivar %@ elimina sus datos de este dispositivo y borra 1 partida que la usa.",
    "Beim Deaktivieren von %@ werden dessen Daten von diesem Gerät entfernt und 1 Spiel gelöscht, das sie verwendet.",
    "Désactiver %@ supprime ses données de cet appareil et supprime 1 partie qui l’utilise.",
    "%@ uitschakelen verwijdert de gegevens van dit apparaat en wist 1 spel dat het gebruikt.",
    "Disattivare %@ rimuove i suoi dati da questo dispositivo ed elimina 1 partita che la usa.")
add("Disabling %@ removes its data from this device and deletes %lld games that use it.",
    "Desactivar %@ elimina sus datos de este dispositivo y borra %lld partidas que la usan.",
    "Beim Deaktivieren von %@ werden dessen Daten von diesem Gerät entfernt und %lld Spiele gelöscht, die sie verwenden.",
    "Désactiver %@ supprime ses données de cet appareil et supprime %lld parties qui l’utilisent.",
    "%@ uitschakelen verwijdert de gegevens van dit apparaat en wist %lld spellen die het gebruiken.",
    "Disattivare %@ rimuove i suoi dati da questo dispositivo ed elimina %lld partite che la usano.")
add("This permanently deletes 1 game and can't be undone.",
    "Esto elimina 1 partida de forma permanente y no se puede deshacer.",
    "Dadurch wird 1 Spiel dauerhaft gelöscht und kann nicht rückgängig gemacht werden.",
    "Cela supprime définitivement 1 partie et est irréversible.",
    "Hiermee wordt 1 spel permanent verwijderd en dit kan niet ongedaan worden gemaakt.",
    "Questo elimina 1 partita in modo permanente e non può essere annullato.")
add("This permanently deletes %lld games and can't be undone.",
    "Esto elimina %lld partidas de forma permanente y no se puede deshacer.",
    "Dadurch werden %lld Spiele dauerhaft gelöscht und können nicht rückgängig gemacht werden.",
    "Cela supprime définitivement %lld parties et est irréversible.",
    "Hiermee worden %lld spellen permanent verwijderd en dit kan niet ongedaan worden gemaakt.",
    "Questo elimina %lld partite in modo permanente e non può essere annullato.")
add("Switches from %@ to %@.", "Cambia de %@ a %@.", "Wechselt von %@ zu %@.", "Passe de %@ à %@.", "Wisselt van %@ naar %@.", "Passa da %@ a %@.")
add("Switches from %@ to %@, deleting 1 game that uses the old league.",
    "Cambia de %@ a %@ y elimina 1 partida que usa la liga anterior.",
    "Wechselt von %@ zu %@ und löscht 1 Spiel, das die alte Liga verwendet.",
    "Passe de %@ à %@ et supprime 1 partie qui utilise l’ancienne ligue.",
    "Wisselt van %@ naar %@ en wist 1 spel dat de oude competitie gebruikt.",
    "Passa da %@ a %@ ed elimina 1 partita che usa la lega precedente.")
add("Switches from %@ to %@, deleting %lld games that use the old league.",
    "Cambia de %@ a %@ y elimina %lld partidas que usan la liga anterior.",
    "Wechselt von %@ zu %@ und löscht %lld Spiele, die die alte Liga verwenden.",
    "Passe de %@ à %@ et supprime %lld parties qui utilisent l’ancienne ligue.",
    "Wisselt van %@ naar %@ en wist %lld spellen die de oude competitie gebruiken.",
    "Passa da %@ a %@ ed elimina %lld partite che usano la lega precedente.")
add("your league", "tu liga", "deine Liga", "ta ligue", "je competitie", "la tua lega")
add("Your %@ plan includes 1 league — tap another to switch.",
    "Tu plan %@ incluye 1 liga: toca otra para cambiar.",
    "Dein %@-Tarif umfasst 1 Liga – tippe auf eine andere, um zu wechseln.",
    "Ton forfait %@ inclut 1 ligue — touche-en une autre pour changer.",
    "Je %@-abonnement bevat 1 competitie — tik op een andere om te wisselen.",
    "Il tuo piano %@ include 1 lega: tocca un’altra per cambiare.")
add("Subscribe to run more at once.", "Suscríbete para usar más a la vez.", "Abonniere, um mehrere gleichzeitig zu nutzen.", "Abonne-toi pour en gérer plusieurs à la fois.", "Abonneer om er meer tegelijk te gebruiken.", "Abbonati per gestirne di più contemporaneamente.")
# DE/IT reorder the args vs the source (%lld=count, %@=plan), so they MUST use
# positional specifiers (%1$ = count, %2$ = plan) — otherwise the Int and String
# args get swapped into the wrong specifier at runtime (garbage/crash).
add("You can enable %lld leagues on the %@ plan.", "Puedes activar %lld ligas con el plan %@.", "Mit dem %2$@-Tarif kannst du %1$lld Ligen aktivieren.", "Tu peux activer %lld ligues avec le forfait %@.", "Je kunt %lld competities inschakelen met het %@-abonnement.", "Con il piano %2$@ puoi attivare %1$lld leghe.")
add("Subscribe to enable more.", "Suscríbete para activar más.", "Abonniere, um mehr zu aktivieren.", "Abonne-toi pour en activer plus.", "Abonneer om er meer in te schakelen.", "Abbonati per attivarne di più.")

# ---- Paywall ----
add("Go Premium", "Hazte Premium", "Premium holen", "Passer à Premium", "Word Premium", "Passa a Premium")
add("Choose a plan", "Elige un plan", "Wähle einen Tarif", "Choisis un forfait", "Kies een abonnement", "Scegli un piano")
add("Subscriptions renew automatically until cancelled. Manage or cancel anytime in the App Store under your Apple ID → Subscriptions.",
    "Las suscripciones se renuevan automáticamente hasta que las canceles. Gestiónalas o cancélalas cuando quieras en la App Store, en tu Apple ID → Suscripciones.",
    "Abos verlängern sich automatisch, bis du sie kündigst. Jederzeit im App Store unter deiner Apple-ID → Abos verwalten oder kündigen.",
    "Les abonnements se renouvellent automatiquement jusqu’à résiliation. Gère ou résilie à tout moment dans l’App Store, sous ton identifiant Apple → Abonnements.",
    "Abonnementen worden automatisch verlengd tot je opzegt. Beheer of zeg op wanneer je wilt in de App Store onder je Apple ID → Abonnementen.",
    "Gli abbonamenti si rinnovano automaticamente fino alla disdetta. Gestiscili o annullali quando vuoi nell’App Store, sotto il tuo ID Apple → Abbonamenti.")
add("Current", "Actual", "Aktuell", "Actuel", "Huidig", "Attuale")
add("Free", "Gratis", "Kostenlos", "Gratuit", "Gratis", "Gratis")
add("No Ads", "Sin anuncios", "Werbefrei", "Sans pub", "Geen advertenties", "Senza pubblicità")
add("Pro", "Pro", "Pro", "Pro", "Pro", "Pro")
add("Ad-supported · 1 league", "Con anuncios · 1 liga", "Mit Werbung · 1 Liga", "Avec pub · 1 ligue", "Met advertenties · 1 competitie", "Con pubblicità · 1 lega")
add("Ads removed · up to 3 leagues", "Sin anuncios · hasta 3 ligas", "Werbefrei · bis zu 3 Ligen", "Sans pub · jusqu’à 3 ligues", "Zonder advertenties · tot 3 competities", "Senza pubblicità · fino a 3 leghe")
add("Ads removed · all leagues + premium", "Sin anuncios · todas las ligas + premium", "Werbefrei · alle Ligen + Premium", "Sans pub · toutes les ligues + premium", "Zonder advertenties · alle competities + premium", "Senza pubblicità · tutte le leghe + premium")

# ---- League downgrade ----
add("Choose your league", "Elige tu liga", "Wähle deine Liga", "Choisis ta ligue", "Kies je competitie", "Scegli la tua lega")
add("Choose your leagues", "Elige tus ligas", "Wähle deine Ligen", "Choisis tes ligues", "Kies je competities", "Scegli le tue leghe")
add("Your plan now includes 1 league. You have %lld enabled — remove %lld to continue.",
    "Tu plan ahora incluye 1 liga. Tienes %lld activadas: quita %lld para continuar.",
    "Dein Tarif umfasst jetzt 1 Liga. Du hast %lld aktiviert – entferne %lld, um fortzufahren.",
    "Ton forfait inclut désormais 1 ligue. Tu en as %lld activées — retires-en %lld pour continuer.",
    "Je abonnement bevat nu 1 competitie. Je hebt er %lld ingeschakeld — verwijder er %lld om door te gaan.",
    "Il tuo piano ora include 1 lega. Ne hai %lld attivate: rimuovine %lld per continuare.")
add("Your plan now includes %lld leagues. You have %lld enabled — remove %lld to continue.",
    "Tu plan ahora incluye %lld ligas. Tienes %lld activadas: quita %lld para continuar.",
    "Dein Tarif umfasst jetzt %lld Ligen. Du hast %lld aktiviert – entferne %lld, um fortzufahren.",
    "Ton forfait inclut désormais %lld ligues. Tu en as %lld activées — retires-en %lld pour continuer.",
    "Je abonnement bevat nu %lld competities. Je hebt er %lld ingeschakeld — verwijder er %lld om door te gaan.",
    "Il tuo piano ora include %lld leghe. Ne hai %lld attivate: rimuovine %lld per continuare.")
add("Keep one — remove the rest", "Conserva una y quita el resto", "Eine behalten – den Rest entfernen", "Garde-en une — retire les autres", "Houd er één — verwijder de rest", "Tienine una: rimuovi le altre")
add("Remove & delete games", "Quitar y eliminar partidas", "Entfernen & Spiele löschen", "Retirer et supprimer les parties", "Verwijderen en spellen wissen", "Rimuovi ed elimina partite")
add("Removes %@ from this device.", "Quita %@ de este dispositivo.", "Entfernt %@ von diesem Gerät.", "Retire %@ de cet appareil.", "Verwijdert %@ van dit apparaat.", "Rimuove %@ da questo dispositivo.")
add("Removes %@ from this device and permanently deletes 1 game that uses it.",
    "Quita %@ de este dispositivo y elimina de forma permanente 1 partida que la usa.",
    "Entfernt %@ von diesem Gerät und löscht dauerhaft 1 Spiel, das sie verwendet.",
    "Retire %@ de cet appareil et supprime définitivement 1 partie qui l’utilise.",
    "Verwijdert %@ van dit apparaat en wist permanent 1 spel dat het gebruikt.",
    "Rimuove %@ da questo dispositivo ed elimina in modo permanente 1 partita che la usa.")
add("Removes %@ from this device and permanently deletes %lld games that use it.",
    "Quita %@ de este dispositivo y elimina de forma permanente %lld partidas que la usan.",
    "Entfernt %@ von diesem Gerät und löscht dauerhaft %lld Spiele, die sie verwenden.",
    "Retire %@ de cet appareil et supprime définitivement %lld parties qui l’utilisent.",
    "Verwijdert %@ van dit apparaat en wist permanent %lld spellen die het gebruiken.",
    "Rimuove %@ da questo dispositivo ed elimina in modo permanente %lld partite che la usano.")
add("Renewed by mistake? Restore your subscription to keep all your leagues.",
    "¿Se renovó por error? Restaura tu suscripción para conservar todas tus ligas.",
    "Versehentlich verlängert? Stelle dein Abo wieder her, um alle Ligen zu behalten.",
    "Renouvelé par erreur ? Restaure ton abonnement pour conserver toutes tes ligues.",
    "Per ongeluk verlengd? Herstel je abonnement om al je competities te behouden.",
    "Rinnovato per errore? Ripristina l’abbonamento per mantenere tutte le tue leghe.")
add("Simulate Pro (testing)", "Simular Pro (pruebas)", "Pro simulieren (Test)", "Simuler Pro (test)", "Pro simuleren (testen)", "Simula Pro (test)")
add("Dev only: unlock all leagues without a purchase (persists across rebuilds).",
    "Solo desarrollo: desbloquea todas las ligas sin comprar (se mantiene tras recompilar).",
    "Nur Entwicklung: schaltet alle Ligen ohne Kauf frei (bleibt nach Neuerstellung erhalten).",
    "Dév uniquement : débloque toutes les ligues sans achat (persiste après reconstruction).",
    "Alleen dev: ontgrendelt alle competities zonder aankoop (blijft behouden na herbouwen).",
    "Solo sviluppo: sblocca tutte le leghe senza acquisto (resta dopo le ricompilazioni).")

# ---- Purchase alerts ----
add("Nothing to restore", "Nada que restaurar", "Nichts wiederherzustellen", "Rien à restaurer", "Niets te herstellen", "Nulla da ripristinare")
add("We couldn't find an active subscription on your Apple ID.",
    "No encontramos una suscripción activa en tu Apple ID.",
    "Wir konnten kein aktives Abo bei deiner Apple-ID finden.",
    "Aucun abonnement actif trouvé sur ton identifiant Apple.",
    "We konden geen actief abonnement vinden op je Apple ID.",
    "Non abbiamo trovato un abbonamento attivo sul tuo ID Apple.")
add("Purchases restored", "Compras restauradas", "Käufe wiederhergestellt", "Achats restaurés", "Aankopen hersteld", "Acquisti ripristinati")
add("You're subscribed", "Te has suscrito", "Du bist abonniert", "Tu es abonné", "Je bent geabonneerd", "Sei abbonato")
add("Your %@ plan is now active.", "Tu plan %@ ya está activo.", "Dein %@-Tarif ist jetzt aktiv.", "Ton forfait %@ est maintenant actif.", "Je %@-abonnement is nu actief.", "Il tuo piano %@ è ora attivo.")
add("Restore failed", "Error al restaurar", "Wiederherstellung fehlgeschlagen", "Échec de la restauration", "Herstellen mislukt", "Ripristino non riuscito")
add("Purchase failed", "Error en la compra", "Kauf fehlgeschlagen", "Échec de l’achat", "Aankoop mislukt", "Acquisto non riuscito")
add("Not available yet", "Aún no disponible", "Noch nicht verfügbar", "Pas encore disponible", "Nog niet beschikbaar", "Non ancora disponibile")
add("Subscriptions aren't available in this build yet. Please check back after the next update.",
    "Las suscripciones aún no están disponibles en esta versión. Vuelve a comprobarlo tras la próxima actualización.",
    "Abos sind in dieser Version noch nicht verfügbar. Schau nach dem nächsten Update wieder vorbei.",
    "Les abonnements ne sont pas encore disponibles dans cette version. Reviens après la prochaine mise à jour.",
    "Abonnementen zijn nog niet beschikbaar in deze versie. Kom terug na de volgende update.",
    "Gli abbonamenti non sono ancora disponibili in questa versione. Riprova dopo il prossimo aggiornamento.")

# ---- Scores search panel extras ----
add("Show", "Mostrar", "Anzeigen", "Afficher", "Tonen", "Mostra")

# ---- Summary cards ----
add("FIXTURES", "PARTIDOS", "SPIELE", "MATCHS", "WEDSTRIJDEN", "PARTITE")
add("PICKS", "SELECCIONES", "TIPPS", "CHOIX", "KEUZES", "SCELTE")
add("RESULTS", "RESULTADOS", "ERGEBNISSE", "RÉSULTATS", "RESULTATEN", "RISULTATI")
add("RESULT", "RESULTADO", "ERGEBNIS", "RÉSULTAT", "RESULTAAT", "RISULTATO")
add("NO CLEAR WINNER", "SIN GANADOR CLARO", "KEIN KLARER SIEGER", "PAS DE VAINQUEUR NET", "GEEN DUIDELIJKE WINNAAR", "NESSUN VINCITORE NETTO")
add("ROUND", "RONDA", "RUNDE", "MANCHE", "RONDE", "TURNO")
add("🏆 WINNER", "🏆 GANADOR", "🏆 GEWINNER", "🏆 VAINQUEUR", "🏆 WINNAAR", "🏆 VINCITORE")
add("🏆 JOINT WINNERS", "🏆 GANADORES CONJUNTOS", "🏆 GEMEINSAME GEWINNER", "🏆 VAINQUEURS EX ÆQUO", "🏆 GEDEELDE WINNAARS", "🏆 VINCITORI A PARI MERITO")
add("⏭️ ROLL THE WEEK", "⏭️ REPETIR LA JORNADA", "⏭️ WOCHE WIEDERHOLEN", "⏭️ REJOUER LA SEMAINE", "⏭️ WEEK OPNIEUW", "⏭️ RIPETI LA GIORNATA")
add("🔄 EVERYONE BACK IN", "🔄 TODOS VUELVEN", "🔄 ALLE WIEDER REIN", "🔄 TOUT LE MONDE REVIENT", "🔄 IEDEREEN TERUG", "🔄 TUTTI DI NUOVO IN GIOCO")
add("Takes it all", "Se lo lleva todo", "Gewinnt alles", "Rafle tout", "Pakt alles", "Si prende tutto")
add("Pot is split", "El bote se reparte", "Topf wird geteilt", "La cagnotte est partagée", "De pot wordt verdeeld", "Il montepremi è diviso")
add("Still in — pick again", "Sigue en juego: vuelve a elegir", "Noch dabei – erneut tippen", "Encore en lice — choisis à nouveau", "Nog in de race — kies opnieuw", "Ancora in gioco: scegli di nuovo")
add("Back in, picks reset", "De vuelta, selecciones reiniciadas", "Wieder dabei, Tipps zurückgesetzt", "De retour, choix réinitialisés", "Terug, keuzes gereset", "Di nuovo in gioco, scelte azzerate")
add("Through to Round %lld (%lld)", "Pasan a la ronda %lld (%lld)", "Weiter in Runde %lld (%lld)", "Qualifiés pour la manche %lld (%lld)", "Door naar ronde %lld (%lld)", "Avanti al turno %lld (%lld)")
add("Eliminated (%lld)", "Eliminados (%lld)", "Ausgeschieden (%lld)", "Éliminés (%lld)", "Afgevallen (%lld)", "Eliminati (%lld)")
add("%lld players through to Round %lld", "%lld jugadores pasan a la ronda %lld", "%lld Spieler weiter in Runde %lld", "%lld joueurs qualifiés pour la manche %lld", "%lld spelers door naar ronde %lld", "%lld giocatori avanti al turno %lld")
add("1 player eliminated", "1 jugador eliminado", "1 Spieler ausgeschieden", "1 joueur éliminé", "1 speler afgevallen", "1 giocatore eliminato")
add("%lld players eliminated", "%lld jugadores eliminados", "%lld Spieler ausgeschieden", "%lld joueurs éliminés", "%lld spelers afgevallen", "%lld giocatori eliminati")
add("%lld eliminated", "%lld eliminados", "%lld ausgeschieden", "%lld éliminés", "%lld afgevallen", "%lld eliminati")

# ---- Share view ----
add("Share", "Compartir", "Teilen", "Partager", "Delen", "Condividi")
add("Fixtures · Round %lld", "Partidos · Ronda %lld", "Spiele · Runde %lld", "Matchs · Manche %lld", "Wedstrijden · Ronde %lld", "Partite · Turno %lld")
add("Results · Round %lld", "Resultados · Ronda %lld", "Ergebnisse · Runde %lld", "Résultats · Manche %lld", "Resultaten · Ronde %lld", "Risultati · Turno %lld")
add("Outcome · Round %lld", "Desenlace · Ronda %lld", "Ausgang · Runde %lld", "Issue · Manche %lld", "Uitkomst · Ronde %lld", "Esito · Turno %lld")
add("Picks due · %@", "Selecciones antes de · %@", "Tipps fällig · %@", "Choix attendus · %@", "Keuzes vóór · %@", "Scelte entro · %@")
add("Picks locked · %@", "Selecciones cerradas · %@", "Tipps gesperrt · %@", "Choix verrouillés · %@", "Keuzes vergrendeld · %@", "Scelte bloccate · %@")
add("Full time · %@", "Final · %@", "Schlusspfiff · %@", "Fin du match · %@", "Eindstand · %@", "Triplice fischio · %@")

# ---- Round status labels (standalone) + anonymous player + wizard action ----
add("Open", "Abierta", "Offen", "Ouverte", "Open", "Aperto")
add("Picks", "Selecciones", "Tipps", "Choix", "Keuzes", "Scelte")
add("Results", "Resultados", "Ergebnisse", "Résultats", "Resultaten", "Risultati")
add("Closed", "Cerrada", "Geschlossen", "Clôturée", "Gesloten", "Chiuso")
add("Player %lld", "Jugador %lld", "Spieler %lld", "Joueur %lld", "Speler %lld", "Giocatore %lld")
add("Enter Results", "Introducir resultados", "Ergebnisse eingeben", "Saisir les résultats", "Resultaten invoeren", "Inserisci risultati")

# ---- Tier raw labels already covered (Free/No Ads/Pro/details) ----

with open("LMS/Localizable.xcstrings", "w", encoding="utf-8") as fh:
    strings = collections.OrderedDict()
    for key, (es, de, fr, nl, it) in T.items():
        locs = collections.OrderedDict()
        for lang, val in (("de", de), ("es", es), ("fr", fr), ("it", it), ("nl", nl)):
            locs[lang] = {"stringUnit": {"state": "translated", "value": val}}
        strings[key] = {"extractionState": "manual", "localizations": locs}
    catalog = collections.OrderedDict()
    catalog["sourceLanguage"] = "en"
    catalog["strings"] = strings
    catalog["version"] = "1.0"
    json.dump(catalog, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

print("Wrote LMS/Localizable.xcstrings with", len(T), "translated keys.")
