  $ $RIM --help
  rim, version 1.4.4, Copyright (c) 2015, esrlabs.com
  
  Usage: [<options>] rim <command> [<args>]
      -v, --version                    Print version info
      -l LOGLEVEL                      log level
                                       one of [debug, info, warn, error, fatal]
      -h, --help                       Print this help
  
  Commands are:
     info : Prints information about RIM modules in <local_module_path> or all modules if omitted
     status : Prints commits and their RIM status
     upload : Upload changes from rim module synchronized to <local_module_path> to remote repository.
     sync : Synchronize specified rim modules with remote repository revisions.
  
  See '.*rim.* help COMMAND' for more information on a specific command. (re)

  $ $RIM help info
  Usage: rim info [<options>] [<local_module_path>]
  Prints information about RIM modules in <local_module_path> or all modules if omitted
  
      -d, --detailed                   print detailed information

  $ $RIM help status
  Usage: rim status [<options>] [<to-rev>|<from-rev>..<to-rev>]
  Prints commits and their RIM status
  
  Without revision arguments checks the current branch and all local ancestors.
  With a single <to-rev> checks that revision and all local ancestors.
  Otherwise checks <to-rev> and ancestors without <from-rev> and ancestors.
  With the --gerrit option, assumes all yet unknown commits to be 'local'.
  
      -d, --detailed                   print detailed status
      -w, --working-copy               print working copy status
      -f, --fast                       fast status assuming remote is clean
          --verify-clean               exit with error code 1 if commits are dirty
          --gerrit                     special gerrit mode which stops on all known commits

  $ $RIM help upload
  Usage: rim upload <local_module_path>
  Upload changes from rim module synchronized to <local_module_path> to remote repository.
      -n, --no-review                  Uploads without review. The changes will be pushed directly to the module's target branch.
  $ $RIM help sync
  Usage: rim sync [<options>] [<local_module_path>]
  Synchronize specified rim modules with remote repository revisions.
  
          --manifest [MANIFEST]        Read information from manifest.
                                       If no manifest file is specified a 'manifest.rim' file will be used.
      -c, --create                     Synchronize module initially to <local_module_path>.
                                       Specify the remote URL and the target revision with the options.
      -a, --all                        Collects all modules from the specified paths.
      -e, --exclude PATTERN_LIST       Exclude all modules of a comma separated list of directories when using sync with -a option.
      -u, --remote-url URL             Set the remote URL of the module.
                                       A relative path will be applied to ssh://gerrit/
      -r, --target-revision REVISION   Set the target revision of the module.
      -i, --ignore PATTERN_LIST        Set the ignore patterns by specifying a comma separated list.
      -m, --message MESSAGE            Message header to provide to each commit.
      -d, --subdir [SUBDIR]            Sync just a subdir from the remote module.
      -s, --split                      Create a separate commit for each module.
      -b, --rebase                     Rebase after successful sync.
