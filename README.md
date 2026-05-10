# PrintWork — Aplikacja desktopowa i mobilna

Aplikacja do zarządzania zleceniami drukarni oraz ewidencji czasu pracy pracowników.
Zbudowana we Flutter — jeden kod działa na Windows (PC) i Android (telefon).

---

## Wymagania wstępne

### 1. Zainstaluj Flutter SDK
Pobierz ze strony: https://docs.flutter.dev/get-started/install/windows

Zainstaluj do `C:\flutter` (zalecane).

Dodaj do zmiennej PATH: `C:\flutter\bin`

Sprawdź instalację:
```
flutter doctor
```

### 2. Zainstaluj Visual Studio (wymagane dla Windows .exe)
Pobierz Visual Studio 2022 Community (bezpłatne):
https://visualstudio.microsoft.com/

Podczas instalacji zaznacz składnik:
**"Desktop development with C++"**

### 3. Włącz obsługę Windows desktop w Flutter
```
flutter config --enable-windows-desktop
```

---

## Uruchomienie projektu

```bash
# Przejdź do folderu projektu
cd printwork_app

# Pobierz zależności
flutter pub get

# Uruchom w trybie deweloperskim (podgląd na żywo)
flutter run -d windows

# Zbuduj instalator .exe (release)
flutter build windows --release
```

Gotowy plik wykonywalny znajdziesz w:
```
build\windows\x64\runner\Release\PrintWork.exe
```

Skopiuj cały folder `Release\` na docelowy komputer — aplikacja działa bez instalacji.

---

## Budowanie na Android (telefon)

```bash
# Zainstaluj Android Studio: https://developer.android.com/studio
# Podłącz telefon przez USB z włączonym debugowaniem USB

flutter run -d android                  # tryb deweloperski
flutter build apk --release             # plik .apk do zainstalowania
```

---

## Struktura projektu

```
lib/
├── main.dart                           # Punkt wejścia, nawigacja
├── db/
│   └── database_helper.dart           # SQLite — wszystkie operacje na bazie
├── models/
│   ├── order.dart                     # Model zlecenia + statusy
│   └── work_entry.dart                # Model czasu pracy + parser CSV/TXT
├── screens/
│   ├── orders/
│   │   ├── orders_screen.dart         # Lista + Kanban zleceń
│   │   ├── order_form_screen.dart     # Formularz nowego/edycji zlecenia
│   │   └── order_detail_screen.dart   # Szczegóły zlecenia
│   └── time_tracking/
│       └── time_tracking_screen.dart  # Import, pulpit, rejestr, anomalie
├── utils/
│   └── theme.dart                     # Kolory, styl aplikacji
└── widgets/
    └── shared_widgets.dart            # Wspólne komponenty UI
```

---

## Baza danych

Plik SQLite zapisywany w:
- **Windows:** `C:\Users\{użytkownik}\Documents\PrintWork\printwork.db`
- **Android:** pamięć wewnętrzna aplikacji

**Backup:** wystarczy skopiować plik `printwork.db`.

---

## Import danych z rejestratora czasu

1. Wyeksportuj plik z rejestratora (format TXT lub CSV, separator tabulatora lub przecinka)
2. W aplikacji otwórz moduł **Czas pracy**
3. Kliknij ikonę importu (strzałka w górę)
4. Wybierz plik — aplikacja automatycznie sparsuje dane i wykryje anomalie

Obsługiwany format kolumn:
```
No | TMNo | EnNo | Name | GMNo | Mode | In/Out | Antipass | ProxyWork | DateTime
```

---

## Planowane rozszerzenia (Etap 2)

- [ ] Eksport raportu PDF / Excel
- [ ] Powiadomienia o zbliżających się terminach zleceń
- [ ] Filtrowanie zleceń po dacie i kliencie
- [ ] Moduł klientów z historią zleceń
- [ ] Wykresy godzin pracy (fl_chart już w zależnościach)
- [ ] Synchronizacja danych PC ↔ telefon przez WiFi

---

## Zależności (pubspec.yaml)

| Pakiet | Wersja | Zastosowanie |
|--------|--------|--------------|
| sqflite / sqflite_common_ffi | ^2.3 | Baza danych SQLite (desktop + mobile) |
| path_provider | ^2.1 | Ścieżki systemowe |
| file_picker | ^8.1 | Wybór pliku importu |
| intl | ^0.19 | Formatowanie dat (pl_PL) |
| fl_chart | ^0.68 | Wykresy (gotowe na Etap 2) |
| csv | ^6.0 | Parser CSV |
| uuid | ^4.4 | Unikalne ID rekordów |
