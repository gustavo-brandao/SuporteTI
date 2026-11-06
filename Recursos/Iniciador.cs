using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("Suporte TI")]
[assembly: AssemblyProduct("Suporte TI")]
[assembly: AssemblyCompany("Gustavo Brand\u00E3o Gimenez")]
[assembly: AssemblyDescription("Caixa de ferramentas para suporte Windows")]
[assembly: AssemblyVersion("0.1.23.0")]
[assembly: AssemblyFileVersion("0.1.23.0")]

internal static class Iniciador
{
    private static int Main()
    {
        string pasta = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(pasta, "Iniciar.ps1");
        string powershell = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");

        try
        {
            if (!File.Exists(script))
            {
                Console.Error.WriteLine("Extraia o pacote completo e mantenha o executavel junto da pasta Modulos e do arquivo Iniciar.ps1.");
                return EncerrarComErro(1);
            }

            var configuracao = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File \"" + script + "\"",
                UseShellExecute = false
            };

            using (Process processo = Process.Start(configuracao))
            {
                processo.WaitForExit();
                return processo.ExitCode == 0 ? 0 : EncerrarComErro(processo.ExitCode);
            }
        }
        catch (Exception erro)
        {
            Console.Error.WriteLine("Nao foi possivel abrir o Suporte TI. " + erro.Message);
            return EncerrarComErro(1);
        }
    }

    private static int EncerrarComErro(int codigo)
    {
        if (!Console.IsInputRedirected)
        {
            Console.WriteLine("Pressione Enter para fechar.");
            Console.ReadLine();
        }
        return codigo;
    }
}
