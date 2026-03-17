using System;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;
using System.IO;
using Renci.SshNet;

public class SFTPOperations
{
    [SqlProcedure]
    public static void UploadToSFTP(
        SqlString host, 
        SqlInt32 port, 
        SqlString username, 
        SqlString password, 
        SqlString localFilePath, 
        SqlString remoteFilePath)
    {
        try
        {
            if (host.IsNull || username.IsNull || password.IsNull || localFilePath.IsNull || remoteFilePath.IsNull)
            {
                SqlContext.Pipe.Send("Error: One or more required parameters are null");
                return;
            }

            if (!File.Exists(localFilePath.Value))
            {
                SqlContext.Pipe.Send("Error: Local file does not exist: " + localFilePath.Value);
                return;
            }

            using (var client = new SftpClient(host.Value, port.Value, username.Value, password.Value))
            {
                SqlContext.Pipe.Send("Connecting to " + host.Value + "...");
                client.Connect();
                
                SqlContext.Pipe.Send("Connected. Uploading file...");
                
                using (var fileStream = File.OpenRead(localFilePath.Value))
                {
                    client.UploadFile(fileStream, remoteFilePath.Value, true);
                }
                
                client.Disconnect();
                SqlContext.Pipe.Send("SUCCESS: File uploaded to " + remoteFilePath.Value);
            }
        }
        catch (Exception ex)
        {
            SqlContext.Pipe.Send("ERROR: " + ex.Message);
            if (ex.InnerException != null)
            {
                SqlContext.Pipe.Send("Inner Exception: " + ex.InnerException.Message);
            }
        }
    }
}
