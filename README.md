# JohnnyFive Sample

![build status](https://travis-ci.org/kbrock/johnny_five_sample.svg)

- [ ] You have a big project
- [ ] You split up the project into multiple sub-projects.
- [ ] You add a build matrix to travis.
- [ ] You don't want to test every matrix entry for every merge or PR.

This project aims to provide a way to state dependencies and know what processes need to be run for a given travis build.

# Inspiration

Projects like [ManageIQ] and [rails] have a build matrix and spend a lot of time on potentially unneeded options. [tech empower] has a slick short circuit implementation. `Makefile` does a great job with detecting dependencies, but it uses file modification dates.

# Possible Next Steps

- [ ] proof of concept
- [ ] extract rule file into `Makefile` or `yaml` format.
- [ ] introduce into `.travis.yml`.
- [ ] Enhance local rake tasks to leverage this logic
- [ ] Write in a language that is installed on linux/travis by default.

# Places to look in this repo

There is nothing of interest in lib, app or others. Rails is just used here because that was the quickest way for me to generate files and dependencies.

- [travis.yml] script that incorporates short circuit logic.
- [johnny_five.rb] short circuit matrix and logic to understand.
- [before_install.sh]  [before_script.sh] scripts that leverage this logic.


[ManageIQ]: https://github.com/ManageIQ/manageiq
[rails]: https://github.com/rails/rails
[Travis]: https://github.com/travis-ci/travis-ci/issues/5007
[Env Vars]: http://docs.travis-ci.com/user/environment-variables/#Default-Environment-Variables
[tech empower]: https://github.com/TechEmpower/FrameworkBenchmarks/blob/master/toolset/run-ci.py#L53
[travis.yml]: .travis.yml#L22-L28
[johnny_five.rb]: build_tools/johnny_five.rb

[before_install.sh]: build_tools/before_install.sh
[before_script.sh]: build_tools/before_script.sh
