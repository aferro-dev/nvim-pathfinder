# nvim-pathfinder

Mappa ad albero bidimensionale a schermo intero per Neovim 0.11+. Ogni cartella appare una sola volta, collegata direttamente ai figli nella colonna successiva. La mappa è centrata orizzontalmente e verticalmente e si riadatta alle espansioni e al ridimensionamento. Cartelle, selezione e scorciatoie usano capsule arrotondate con glifi Nerd Font. I rami partono direttamente dai nodi e usano linee sottili, le cartelle hanno uno sfondo distinto e la selezione usa un accento lilla su una palette dedicata blu-viola scura. Le icone sono uniformate in azzurro per le cartelle e grigio-lavanda per i file; i glifi provengono da `mini.icons` o `nvim-web-devicons`, con fallback se non disponibili.

Pathfinder sostituisce netrw: parte con `nvim`, `nvim .`, `nvim /percorso` e quando si apre una directory con `:edit`. Anche `:Explore` usa Pathfinder. Avviando Neovim con un file si entra normalmente nell'editor. Per disabilitare questa integrazione usare `setup({ default_explorer = false })` prima del caricamento dei plugin.

`:Pathfinder` apre la repository Git (in alternativa la directory corrente), espande gli antenati e seleziona il file corrente. Le altre cartelle partono chiuse. La mappa conserva split, buffer e modifiche non salvate. `:Pathfinder /percorso` sceglie una radice esplicita.

| Key | Action |
| --- | --- |
| `j/k`, `↓/↑` | Next/previous node; expand the adjacent branch to keep depth, or move up when needed |
| `h/l`, `←/→` | Previous/next column, selecting the nearest node vertically |
| `Enter` | Open file or toggle directory; expanding selects the first child |
| `Space` | Toggle directory; expanding selects the first child |
| `zo` / `zc` | Expand / collapse node |
| `zR` / `zM` | Expand all nodes / collapse all nodes |
| `Backspace`, `-` | Select parent |
| `R` | Refresh tree, preserving expanded nodes |
| `q`, `Esc`, `Ctrl-P` | Close Pathfinder and return to the original window |

`zR` keeps the selected node. `zM` selects its ancestor in the root directory when necessary. Bulk expansion follows the configured filters and never traverses symbolic links.

Il percorso compare nella barra superiore, le scorciatoie nella cornice inferiore. I nomi lunghi vengono abbreviati; la vista scorre per seguire il nodo selezionato. I movimenti supportano un conteggio (`3j`). Ai bordi ci si ferma.

I file nascosti sono visibili; `.git` è esclusa. Le directory si caricano quando vengono espanse e precedono i file, ordinati per nome. I link simbolici restano foglie per evitare cicli. La mappa si concentra sull'esplorazione: non include operazioni di scrittura sui file o indicatori Git.

## Installazione Lua

Aggiungere la directory del plugin al runtimepath, oppure installarla con il proprio plugin manager, quindi:

```lua
require('pathfinder').setup({ hidden = true, ignored = { '.git' } })
vim.keymap.set('n', '<C-p>', '<cmd>Pathfinder<CR>', { silent = true })
```

## Nix / Nixvim

Pacchetto standalone: `nix build path:.` (usa una flake path perché include anche i file non ancora aggiunti a Git).

In un modulo Home Manager che usa Nixvim:

```nix
{ pkgs, ... }: {
  imports = [ /percorso/nvim-pathfinder/nix/nixvim.nix ];
}
```

Oppure aggiungere a `programs.nixvim.extraPlugins`:

```nix
(import /percorso/nvim-pathfinder/default.nix { inherit pkgs; })
```

La flake espone anche `packages.<system>.default` e `homeManagerModules.default` (richiede il modulo Home Manager di Nixvim). Per una dipendenza locale durante lo sviluppo usare un percorso assoluto accessibile al processo di build. Il pacchetto Nix contiene una copia immutabile: ricostruire Nixvim dopo le modifiche.

## Verifica

```sh
nvim --headless -u NONE -l tests/smoke.lua
nvim --headless -u NONE -l tests/grid.lua
python3 tests/startup.py
```
