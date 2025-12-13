    const socket = new WebSocket("ws://localhost:8080/ws");

    socket.addEventListener("open", function() {
        if (localStorage.getItem("userId") === null) {
            var random_nums = window.crypto.getRandomValues(new Uint8Array(16));    
            var str = ""; 

            for (let i = 0; i < random_nums.length; i++) { 
                str = str.concat(String.fromCharCode(random_nums[i])); 
            } 

            var encoded = btoa(str); 
            encoded = encoded.replaceAll("/", "_");
            encoded = encoded.replaceAll("+", "-");
            encoded = encoded.replaceAll("=", "");

            window.history.replaceState(null, "", "?userid=" + encoded);
            localStorage.setItem("userId", encoded);

            var user_id = localStorage.getItem("userId");
            const identification_json = JSON.stringify({ userId: user_id });
            socket.send(identification_json);
        } else {
            var user_id = localStorage.getItem("userId");
            window.history.replaceState(null, "", "?userid=" + user_id);

            const identification_json = JSON.stringify({ userId: user_id });
            socket.send(identification_json);
        }
    });

    socket.addEventListener("message", function(event) {
        var output_box = document.getElementById("output-box");
        output_box.innerHTML = event.data;
    });

    function debounce(func, delay) {
        let timeout; 
        return function (...args) {
            clearTimeout(timeout);
            timeout = setTimeout(() => {
                func.apply(this, args);
            }, delay);
        };
    }

    var editor = ace.edit("editor");
    document.getElementById("editor").style.fontSize='15px';
    editor.setTheme("ace/theme/tokyonight");
    editor.setKeyboardHandler("ace/keyboard/vim");
    editor.session.setMode("ace/mode/d");

    function save_content() {
        localStorage.setItem("editorContent", editor.getValue());
    }

    var debounced_save = debounce(save_content, 5000);
    
    editor.getSession().on('change', function() {
        debounced_save();
    });

    var container = document.getElementById("container");    
    container.style.display = "flex";
    container.style.flexDirection = "row";

    var editor_element = document.getElementById("editor");
    editor_element.style.position = "relative";
    editor_element.style.flex = "1";
    editor_element.style.height = `${window.innerHeight - 95}px`;
    editor_element.style.boxShadow = "5px 5px 5px 5px #000000";
    
    if (localStorage.getItem("editorContent") !== null) {
        editor.setValue(localStorage.getItem("editorContent"), -1);
    }

    var output_box = document.getElementById("output-box");
    output_box.style.position = "relative";
    output_box.style.flex = "1";
    output_box.style.height = `${window.innerHeight - 95}px`;
    output_box.style.boxShadow = "5px 5px 5px 5px #000000";
    output_box.style.marginLeft = "25px";

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
        const request_json = JSON.stringify({ userId: localStorage.getItem("userId"), content: editor.getValue() });
        socket.send(request_json);
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


