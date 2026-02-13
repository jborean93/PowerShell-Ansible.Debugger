using System;

namespace Ansible.Debugger;

public readonly record struct PSRPMessage(
    PSRPDestination Destination,
    PSRPMessageType MessageType,
    Guid RunspacePoolId,
    Guid PipelineId,
    string Data);
