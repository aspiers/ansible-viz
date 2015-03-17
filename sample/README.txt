RoleA is designed to have at least one of everything.

roleA/defaults/main.yml
    Sets defA.
roleA/vars/main.yml
    Sets varAmain.
roleA/vars/maininc.yml
    Sets varAmaininc.
roleA/vars/extra.yml
    Sets varAextra.
roleA/tasks/main
    Includes vars from maininc.yml
    Sets + uses factAmain.
    Uses defA, varAmain, varAmaininc, varAundef (UNDEFINED).
roleA/tasks/taskA
    Includes vars from extra.yml
    Includes taskB.
    Sets factAunused (UNUSED).
    Uses defA, varAmain, varAextra, factB.
roleA/tasks/taskB
    Sets factB.


Playbook A just uses stuff from role A.
    Uses roleA.
    Uses taskA.


Role1 is a copy of roleA, but also:
    Includes roleA via meta/main.yml.
    Everything with an A or B in it has a 1 or 2 instead.
    All tasks use both versions of the vars/facts the roleA versions do.
    Task1 does NOT directly include taskB, only task2.


Playbook 1:
    Uses roleA and role1.
    Uses taskA and task1.



TODO:
  Test variable precedence, IE vars that override each other.
