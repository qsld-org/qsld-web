FROM ubuntu:25.10

# update the system 
RUN apt-get update -y && apt-get upgrade -y

# install dmd
RUN apt-get install -y wget gnupg && \
    wget https://netcologne.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list && \
    apt-get update --allow-insecure-repositories && \
    apt-get -y --allow-unauthenticated install --reinstall d-apt-keyring && \
    apt-get update && \
    apt-get install -y dmd-compiler && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#install rdmd
RUN wget https://raw.github.com/dlang/tools/master/rdmd.d && \
    dmd rdmd.d && \ 
    mv rdmd /usr/local/bin/ && \
    rm rdmd.o rdmd.d

# install qsld
RUN apt-get update && \
    apt-get install -y git && \
    git clone https://github.com/aroario2003/qsld.git

# build qsld
RUN  cd ./qsld && \
    chmod +x ./build.d && \
    ./build.d && \
    mv ./libqsld.a /usr/local/lib/ && \
    cd .. && \
    mv ./qsld /usr/local/include/

# install extra dependencies
RUN apt-get update -y && apt-get install -y vim neovim texlive-latex-base texlive-fonts-recommended texlive-fonts-extra texlive-latex-extra tex-common bash imagemagick

# install quantikz
RUN wget https://mirrors.ctan.org/graphics/pgf/contrib/quantikz/quantikz.sty && \
    mkdir -p /usr/local/share/texmf/tex/latex/quantikz/ && \
    mv ./quantikz.sty /usr/local/share/texmf/tex/latex/quantikz/ && \
    mktexlsr

# install blochsphere visualization package
RUN mkdir -p /usr/local/share/texmf/tex/latex/blochsphere/ && \
    git clone https://github.com/matthewwardrop/latex-blochsphere.git && \
    cd latex-blochsphere && \
    pdflatex blochsphere.ins && \
    mv ./blochsphere.sty /usr/local/share/texmf/tex/latex/blochsphere/ && \
    mktexlsr




