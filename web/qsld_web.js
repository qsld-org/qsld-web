    const socket = new WebSocket("ws://localhost:8080/ws");

    var editor = ace.edit("editor");
    document.getElementById("editor").style.fontSize='15px';
    editor.setTheme("ace/theme/tokyonight");
    editor.setKeyboardHandler("ace/keyboard/vim");
    editor.session.setMode("ace/mode/d");

    var editor_element = document.getElementById("editor");
    editor_element.style.position = "absolute";
    editor_element.style.height = `${window.innerHeight - 95}px`;
    editor_element.style.width = `${window.innerWidth / 2}px`;
    editor_element.style.boxShadow = "5px 5px 5px 5px #000000";

    var top_bar = document.getElementById("top-bar");
    top_bar.style.height = "50px";
    top_bar.style.marginBottom = "25px";
    top_bar.style.width = `${window.innerWidth}`;
    top_bar.style.backgroundColor = "#1a1b26";
    top_bar.style.boxShadow = "5px 5px 5px 5px #000000";
    top_bar.style.textAlign = "center";

    var run_btn = document.getElementById("run-btn");
    run_btn.style.color = "#9ece6a";
    run_btn.style.backgroundColor = "#1a1b26";
    run_btn.style.fontFamily = "Hack Nerd Font";
    run_btn.style.fontSize = "20px";
    run_btn.style.border = "none";
    run_btn.title = "run code";
    run_btn.style.marginTop = "15px";

    run_btn.addEventListener('mouseover', function() {
        run_btn.style.backgroundColor = "#a9b1d6";
    });

    run_btn.addEventListener('mouseleave', function() {
        run_btn.style.backgroundColor = "#1a1b26";
    });

    run_btn.addEventListener('click', function() {
        socket.send(editor.getValue());
    });

    var vim_mode_label = document.getElementById("vim-mode-label");
    vim_mode_label.style.color = "#c0caf5";

    var vim_mode_select = document.getElementById("vim-mode-select");
    vim_mode_select.style.backgroundColor = "#1a1b26";
    vim_mode_select.style.color = "#c0caf5";
    vim_mode_select.onchange = function() {
        var value = this.value;
        console.log("changed");
        if (value === "on") {
            editor.setKeyboardHandler("ace/keyboard/vim");
        } else if (value === "off") {
            editor.setKeyboardHandler("");
        }
    }
    
    window.addEventListener('resize', function() {
        editor_element.style.height = `${window.innerHeight - 95}px`;
        editor_element.style.width = `${window.innerWidth / 2}px`;
        editor.resize();
    });


