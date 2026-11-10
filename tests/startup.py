"""Exercise real startup events in isolated headless Neovim processes."""
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / 'project').mkdir()
    file = root / 'project/example.lua'
    file.write_text('return true\n')
    init = root / 'init.lua'
    for name, args, explorer, followup in [
        ('empty startup', [], True, ''),
        ('directory startup', [str(root / 'project')], True, ''),
        ('file startup', [str(file)], False, ''),
        ('edit directory', [str(file)], True, "vim.cmd.edit(vim.fn.fnameescape(" + repr(str(root / 'project')) + "))"),
        ('Explore command', [str(file)], True, "vim.cmd.Explore(" + repr(str(root / 'project')) + ")"),
    ]:
        init.write_text("vim.opt.runtimepath:prepend(" + repr(str(repo)) + ")\n"
            + "vim.opt.swapfile = false\nvim.cmd('runtime plugin/pathfinder.lua')\n"
            + "vim.api.nvim_create_autocmd('VimEnter', { callback = function()\n"
            + "vim.schedule(function()\n" + followup + "\nvim.schedule(function()\n"
            + "local ok, err = pcall(function()\n"
            + "assert((vim.bo.filetype == 'pathfinder') == " + str(explorer).lower() + ")\n"
            + ("require('pathfinder').close(); assert(vim.bo.buftype == '')\n" if explorer else '')
            + "end)\nif not ok then io.stderr:write(tostring(err)); vim.cmd('cquit 1') else vim.cmd('qa!') end\n"
            + "end) end) end })\n")
        result = subprocess.run(['nvim', '--headless', '-i', 'NONE', '-u', str(init), *args],
            cwd=tmp, text=True, capture_output=True, timeout=15,
            env=dict(os.environ, NVIM_LOG_FILE=str(root / 'nvim.log')))
        assert result.returncode == 0, f'{name}: {result.stderr}'
        assert 'Error' not in result.stderr, f'{name}: {result.stderr}'
        print(f'{name}: passed')
