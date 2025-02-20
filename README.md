# Joogle is a search engine for the jai standard modules insipred by [Tsoding's Coogle C Search Engine](https://youtube.com/playlist?list=PLpM-Dvs8t0VYhYLxY-i7OcvBbDsG4izam&feature=shared)
## NOTE: This is still a very early concept and not production ready, expect to rummage around the main.jai if you want to fully integrate this into your workflow and understand how it works

# Quick Start
- In order to use the search functionality you first need to build a procedure listing file from the jai standard modules.
- The following command tries to compile all of the modules on all of the major opertaing systems, so expect to see linking errors when you run this.
- The procedure listing file is output to modules.procs
```console
jai main.jai - generate
```

- In order to run queries, use the following commands to compile and run the search tool
```console
jai main.jai - build
search "(*String_Builder) -> ()" 65
```

- A query can also be ran at compile time using jai's interpreter
- This is very slow and not usually recommended
```console
jai main.jai - search "(*String_Builder) -> ()" 65
```

https://github.com/user-attachments/assets/8888eaf5-05bb-4b48-9c30-462074c7d8ff




