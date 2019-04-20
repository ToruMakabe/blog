workflow "HUGO" {
  on = "push"
  resolves = ["Build_And_Deploy"]
}

action "master" {
  uses = "actions/bin/filter@master"
  args = "branch master"
}

action "Build_And_Deploy" {
  needs = "master"
  uses = "./.action"
  env = {
    TARGET_REPO = "ToruMakabe/ToruMakabe.github.io"
    HUGO_VERSION = "0.55.2"
  }
  secrets = ["GH_PAT"]
}
