# QSLD-Web

> [!WARNING]
> This program is in early development. Use at your own risk.

# Introduction

This is the online playground for the QSLD quantum simulation library. If you are unfamiliar with qsld, you can check it out [here](https://github.com/qsld-org/qsld). This application is mainly meant for locally hosting and possibly self hosting if you are willing to accept the security risks. The main goal of this project is to give people an easier way to get started with QSLD without having to install the D compiler or setup an environment for development until they are familiar with the API and have a decent understanding of the library. 

# Dependencies

- `docker`
- `apache`
- `dub`
- `linux`
- `systemd`

## Installing Dependencies

### Docker

Docker should be available in most modern Linux distributions repositories, so you can just install it with your package manager.

#### Arch Linux

```console
$ sudo pacman -S docker
```

#### Debian/Ubuntu

Refer to this [website](https://docs.docker.com/engine/install/ubuntu/) on how to install the official docker engine.

#### Fedora

Refer to this [website](https://docs.docker.com/engine/install/fedora/) on how to install the official docker engine.

### Apache

#### Arch Linux 

```console
$ sudo pacman -S apache
```

#### Debian/Ubuntu

```console
$ sudo apt install -y apache2
```

#### Fedora

```console
$ sudo dnf install httpd -y
```

### Dub

Dub is the official package manager for the D programming language which this playground as well as QSLD are written in. 

#### Arch Linux

```console
$ sudo pacman -S dlang
```

#### Debian/Ubuntu

In order to install it on Debian/Ubuntu or systems based on the former, you will first have to enable the d-apt repository by following the instructions at this [page](https://d-apt.sourceforge.io/). 

Once the repository is enabled you can just install dub by doing:

```console
$ sudo apt install -y dub
```

#### Fedora

In order to install on fedora you can download the rpm file for dmd from this [page](https://dlang.org/download.html#dmd) as dub should be shipped with this package. 


## Installing Qsld-Web

You should first git clone the project into a directory of your choice

```console
$ git clone https://github.com/aroario2003/qsld-web.git
```

Once that is done, you should then cd into the directory and build the docker image for the containers which will be run by Qsld-Web, however, before that can be done, the docker daemon must be started. To do this on any systemd based system, you can simply type:

```console
$ sudo systemctl start docker
```

This will start docker for your current boot but if you want it to always be started on boot and also get started now, then you should do:

```console
$ sudo systemctl enable --now docker
```

Now that the docker daemon is started you can now build the qsld_web docker image from the Dockerfile in the root of the project by doing:

```console
$ docker build -t qsld_web .
```

This will build a docker container image called qsld_web that will be used by the application in order to create docker containers.

Once the docker image is built, you can proceed to build the project itself, by doing:

```console
$ dub build
```

This will download a dependency for the project known as vibe.d which is mainly used for http and asynchronous operations. 

Once the project is built, a binary called **qsld-web** should appear in the root of the project. You should move this to `/usr/local/bin` by doing:

```console
$ sudo mv ./qsld-web /usr/local/bin/
```

**NOTE**: Although it is not a strict requirement to move the binary to `/usr/local/bin`, it is recommended, as the systemd service assumes that it will be there and it not being present will break the systemd service.

Once the binary has been moved to `/usr/local/bin`, you can then move the systemd service to a place where systemd will recognize it by doing:

```console
$ sudo cp ./services/qsld_web.service /etc/systemd/system/
```

You should then immediately reload systemd's database of daemons

```console
$ sudo systemctl daemon-reload
```

### Configuring Qsld-Web

In order to configure sane defaults for the backend service you must add environment variables to a file which systemd will use to feed to the backend code. The file should be located at `/etc/qsld_web/qsld_web.env`, if it dpes not exist than you should create it:

```console
$ sudo mkdir -p /etc/qsld_web
```

and then create the file

```console
$ sudo touch /etc/qsld_web/qsld_web.env
```

The environment variables you can put in the file are as follows:

```
QSLD_WEB_CONTAINERS_MEMORY=1.5
QSLD_WEB_CONTAINERS_CPUS=1
QSLD_WEB_FRONTEND_ORIGIN="http://localhost:8000"
QSLD_WEB_DOCKER_CONTAINER_LIMIT=15
```

The values specified here for these variables are the defaults, if you would like to change any of them then you should specify the new value in the file. The memory value is in GB, the cpu value is in 1 entire cpu.

Once these variables have been modified to correct values for your setup, you can then and only then start the backend service:

```console
$ sudo systemctl start qsld_web.service
```

Or if you want it to start on every boot then you can do:

```console
$ sudo sytemctl enable --now qsld_web.service
```

## Installing The Apache Web Server

Apache will be used to serve the frontend code and UI. Make sure that you installed the apache web server as directed above. Once you have done that, you can then modify the the config file at `/etc/httpd/conf/httpd.conf` if you are on **Arch Linux** or **Fedora** and `/etc/apache2/apache2.conf` if you are on **Debian/Ubuntu**, however you would like. It is recommended that you change the port that apache serves on to something other than 80, by default the backend will assume 8000 but you can use any port of your choice that is greater than 1024. Be aware that if you change the port to something other than 8000, you will have to change an environment variable for the backend later. 

Once you have modified the configuration to your liking, you can then move all the frontend code to the correct directory based on your system:

### Arch Linux

```console
$ sudo cp -r ./web/* /srv/http/
```

### Debian/Ubuntu or Fedora

```console
$ sudo cp -r ./web/* /var/www/html/
```

Once you have moved the frontend code to the correct directory, you can then start the apache web server:

```console
$ sudo systemctl start httpd
```

As before that will only start it for your current boot, if you would like it to start on every boot including right now:

```console
$ sudo systemctl enable --now httpd
```

### Using https

As this application is meant mainly for local hosting, https support is not built in, if you would like to use https for security purposes if exposing the application to the internet, you should use a reverse proxy like **nginx**. As well as find your own self signed certificates for TLS.

# Notice of Security Risks

This application as afforementioned is mainly meant for local hosting and therefore does not take all the security measures neccessary to prevent certain types of attacks when exposed to the internet. If you as the hoster plan to expose the application to the internet you should be aware of these risks and take action as deemed neccessary.

# Notice of Limited Capacity

The application only supports as many users as their are docker containers allowed. Therefore, if you only allow for 15 docker containers, only 15 users will be able to use the application at the same time. Allowing for many docker containers at the same time with high memory and cpu limits can cause a system to crash or get very slow, so be very careful and wise about the limits you choose.

# Contributing

All contributions are welcome, you should submit all contributions through pull requests and make sure that all code is readable and any documentation changed has correct grammar, spelling and punctuation.

# License

This project is licensed under the MIT license.
