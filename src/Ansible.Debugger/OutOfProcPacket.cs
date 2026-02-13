using System;
using System.Buffers;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Xml.Linq;

namespace Ansible.Debugger;

public readonly record struct OutOfProcPacket(
    string Type,
    Guid PSGuid,
    string? Stream,
    PSRPFragment[] Fragments,
    PSRPMessage[] Messages,
    string Raw)
{
    public static OutOfProcPacket Parse(
        string line,
        Dictionary<ulong, List<byte>> fragements)
    {
        XElement element = XElement.Parse(line);

        string elementType = element.Name.LocalName;
        string psGuidRaw = element.Attribute("PSGuid")?.Value
            ?? throw new InvalidDataException("Missing PSGuid attribute");
        if (!Guid.TryParse(psGuidRaw, out Guid psGuid))
        {
            throw new InvalidDataException($"Invalid PSGuid value: {psGuidRaw}");
        }

        string? stream = null;
        PSRPFragment[] fragments = [];
        PSRPMessage[] messages = [];
        if (elementType == "Data")
        {
            stream = element.Attribute("Stream")?.Value
                ?? throw new InvalidDataException("Missing Stream attribute on Data element");

            string fragmentB64 = element.Value;
            (fragments, messages) = ParseFragments(fragmentB64, fragements);
        }

        return new(elementType, psGuid, stream, fragments, messages, line);
    }

    [SkipLocalsInit]
    private static (PSRPFragment[], PSRPMessage[]) ParseFragments(
        string base64,
        Dictionary<ulong, List<byte>> fragmentPool)
    {
        int fragmentLength = base64.Length * 3 / 4;

        List<PSRPFragment> fragments = [];
        List<PSRPMessage> messages = [];
        byte[]? rentedBytes = null;
        try
        {
            Span<byte> buffer = fragmentLength <= 256
                ? stackalloc byte[256]
                : (rentedBytes = ArrayPool<byte>.Shared.Rent(fragmentLength));

            buffer = buffer[..fragmentLength];
            Convert.TryFromBase64String(base64, buffer, out _);

            while (buffer.Length > 21)
            {
                PSRPFragment frag = new(
                    ObjectId: BinaryPrimitives.ReadUInt64BigEndian(buffer),
                    FragmentId: BinaryPrimitives.ReadUInt64BigEndian(buffer[8..]),
                    Start: (buffer[16] & 0x1) != 0,
                    End: (buffer[16] & 0x2) != 0);
                fragments.Add(frag);

                int blobLength = BinaryPrimitives.ReadInt32BigEndian(buffer[17..]);
                buffer = buffer[21..];
                ReadOnlySpan<byte> blob = buffer[..blobLength];

                if (frag.Start && frag.End)
                {
                    // Optimisation, we don't need to worry about fragment
                    // reassembly if this is the only fragment
                    messages.Add(ParseMessage(blob));
                }
                else if (frag.Start)
                {
                    List<byte> fragPool = [.. blob];
                    fragmentPool[frag.ObjectId] = fragPool;
                }
                else
                {
                    List<byte> fragPool = fragmentPool[frag.ObjectId];
                    fragPool.AddRange(blob);

                    if (frag.End)
                    {
                        blob = CollectionsMarshal.AsSpan(fragPool);
                        messages.Add(ParseMessage(blob));
                        fragmentPool.Remove(frag.ObjectId);
                    }
                }

                buffer = buffer[blobLength..];
            }
        }
        finally
        {
            if (rentedBytes is not null)
            {
                ArrayPool<byte>.Shared.Return(rentedBytes);
            }
        }

        return ([.. fragments], [.. messages]);
    }

    private static PSRPMessage ParseMessage(ReadOnlySpan<byte> buffer)
    {
        ReadOnlySpan<byte> data = buffer[40..];
        if (data.Length > 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF)
        {
            // Skip UTF-8 BOM if present
            data = data[3..];
        }

        return new(
            (PSRPDestination)BinaryPrimitives.ReadInt32LittleEndian(buffer),
            (PSRPMessageType)BinaryPrimitives.ReadInt32LittleEndian(buffer[4..]),
            new Guid(buffer[8..24]),
            new Guid(buffer[24..40]),
            Encoding.UTF8.GetString(data));
    }
}
