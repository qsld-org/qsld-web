    const server = "localhost:8080";
    const code_socket = new WebSocket(`ws://${server}/ws`);

    // creates the user id to identify the user
    function identify_user() {
        var identification_json;
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
            identification_json = JSON.stringify({ userId: user_id });
        } else {
            var user_id = localStorage.getItem("userId");
            window.history.replaceState(null, "", "?userid=" + user_id);

            identification_json = JSON.stringify({ userId: user_id });
        }

        return identification_json;
    }

    function debounce(func, delay) {
        let timeout; 
        return function (...args) {
            clearTimeout(timeout);
            timeout = setTimeout(() => {
                func.apply(this, args);
            }, delay);
        };
    }

    function save_content() {
        localStorage.setItem("editorContent", editor.getValue());
    }

    async function put_images_in_output_box(images, user_id) {
        for (let i = 0; i < images.length; i++) {
            var image_url = `http://${server}/artifact/${user_id}/${images[i]}`;
            const resp = await fetch(image_url);
            const blob = await resp.blob();
            const blob_url = URL.createObjectURL(blob);

            const image_elem = document.createElement("img");
            image_elem.id = "image";
            image_elem.src = blob_url;

            const image_dl_elem = document.createElement("a");
            image_dl_elem.id = "image-download";
            image_dl_elem.href = blob_url;
            image_dl_elem.download = images[i];
            image_dl_elem.style.marginTop = "6px";
            image_dl_elem.style.marginBottom = "6px";
            image_dl_elem.textContent = "Download";

            output_box.appendChild(image_elem);
            output_box.appendChild(image_dl_elem);
        }
    }

    let run_enabled = true;
    function idleTimer() {
        var t;

        //window.onload = resetTimer;
        window.onmousemove = resetTimer; 
        window.onmousedown = resetTimer; 
        window.onclick = resetTimer;     
        window.onscroll = resetTimer;    
        window.onkeypress = resetTimer;  

        function disconnect() {
            run_enabled = false;
            run_btn.style.color = "#2f2f2f";
            alert("You have been inactive for too long, you have been disconected from the server");
            code_socket.close();

            window.onmousemove =
            window.onmousedown =
            window.onclick = 
            window.onscroll = 
            window.onkeypress = null;

            clearTimeout(t);
        }

        function resetTimer() {
            clearTimeout(t);
            t = setTimeout(disconnect, 1800000);  
        }
    }
    idleTimer();

    // sends the user id to the backend 
    var identification_json = identify_user();
    code_socket.addEventListener("open", function() {
        code_socket.send(identification_json);
    });

    // delays actions for some amount of time
    var editor = ace.edit("editor");
    document.getElementById("editor").style.fontSize='15px';
    editor.setTheme("ace/theme/tokyonight");
    editor.setKeyboardHandler("ace/keyboard/vim");
    editor.session.setMode("ace/mode/d");

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
        if (!run_enabled) {
            alert("The run button is not functional while the backend is disconnected, please reload the page to try and get a slot to execute code, please do not spam reload ;)");
            return;
        }
        const request_json = JSON.stringify({ userId: localStorage.getItem("userId"), content: editor.getValue() });
        code_socket.send(request_json);
    });

    var clear_btn = document.getElementById("clear-btn");
    clear_btn.style.backgroundColor = "#7aa2f7";
    clear_btn.style.color = "#1a1b26";
    clear_btn.style.fontSize = "20px";
    clear_btn.style.border = "none";
    clear_btn.title = "clear code output";
    clear_btn.style.marginTop = "15px";
    clear_btn.style.borderRadius = "10px";
    clear_btn.style.marginRight = "10px";
    clear_btn.style.cursor = "pointer";

    clear_btn.addEventListener('click', function() {
        output_box.innerHTML = "";
    });

    var reset_btn = document.getElementById("reset-btn");
    reset_btn.style.backgroundColor = "#f7768e";
    reset_btn.style.color = "#1a1b26";    
    reset_btn.style.fontSize = "20px";
    reset_btn.style.border = "none";
    reset_btn.title = "reset everything";
    reset_btn.style.marginTop = "15px";
    reset_btn.style.borderRadius = "10px";
    reset_btn.style.marginRight = "10px";
    reset_btn.style.cursor = "pointer";
    
    reset_btn.addEventListener('click', function() {
        output_box.innerHTMl = "";
        localStorage.removeItem("editorContent");
        window.location.reload();
    });

    // recieves and parses the messages from the backend
    code_socket.addEventListener("message", async function(event) {
        var output_box = document.getElementById("output-box");
        const json_obj = JSON.parse(event.data);

        if (json_obj.contentType === "output") {
            output_box.innerHTML += json_obj.output;
        } else if (json_obj.contentType === "message") {
            output_box.innerHTML += json_obj.message;
        } else if (json_obj.contentType === "images") {
            const images = json_obj.images;
            const user_id = localStorage.getItem("userId");
            put_images_in_output_box(images, user_id);
        } else if (json_obj.contentType === "notification") {
            if (json_obj.type === "busy") { 
                run_enabled = false;
                run_btn.style.color = "#2f2f2f";
                alert(json_obj.notification);
            }
        }
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


