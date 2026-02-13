namespace Ansible.Debugger;

public readonly record struct PSRPFragment(
    ulong ObjectId,
    ulong FragmentId,
    bool Start,
    bool End);
