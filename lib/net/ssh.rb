# Make sure HOME is set, regardless of OS, so that File.expand_path works
# as expected with tilde characters.
ENV['HOME'] ||= ENV['HOMEPATH'] ? "#{ENV['HOMEDRIVE']}#{ENV['HOMEPATH']}" : Dir.pwd

require 'logger'

require 'net/ssh/config'
require 'net/ssh/errors'
require 'net/ssh/loggable'
require 'net/ssh/transport/session'
require 'net/ssh/authentication/session'
require 'net/ssh/connection/session'

module Net

  # Net::SSH is a library for interacting, programmatically, with remote
  # processes via the SSH2 protocol. Sessions are always initiated via
  # Net::SSH.start. From there, a program interacts with the new SSH session
  # via the convenience methods on Net::SSH::Connection::Session, by opening
  # and interacting with new channels (Net::SSH::Connection:Session#open_channel
  # and Net::SSH::Connection::Channel), or by forwarding local and/or
  # remote ports through the connection (Net::SSH::Service::Forward).
  #
  # The SSH protocol is very event-oriented. Requests are sent from the client
  # to the server, and are answered asynchronously. This gives great flexibility
  # (since clients can have multiple requests pending at a time), but it also
  # adds complexity. Net::SSH tries to manage this complexity by providing
  # some simpler methods of synchronous communication (see Net::SSH::Connection::Session#exec!).
  #
  # In general, though, and if you want to do anything more complicated than
  # simply executing commands and capturing their output, you'll need to use
  # channels (Net::SSH::Connection::Channel) to build state machines that are
  # executed while the event loop runs (Net::SSH::Connection::Session#loop).
  #
  # Net::SSH::Connection::Session and Net::SSH::Connection::Channel have more
  # information about this technique.
  #
  # = "Um, all I want to do is X, just show me how!"
  #
  # == X == "execute a command and capture the output"
  #
  #   Net::SSH.start("host", "user", password: "password") do |ssh|
  #     result = ssh.exec!("ls -l")
  #     puts result
  #   end
  #
  # == X == "forward connections on a local port to a remote host"
  #
  #   Net::SSH.start("host", "user", password: "password") do |ssh|
  #     ssh.forward.local(1234, "www.google.com", 80)
  #     ssh.loop { true }
  #   end
  #
  # == X == "forward connections on a remote port to the local host"
  #
  #   Net::SSH.start("host", "user", password: "password") do |ssh|
  #     ssh.forward.remote(80, "www.google.com", 1234)
  #     ssh.loop { true }
  #   end
  module SSH
    # This is the set of options that Net::SSH.start recognizes. See
    # Net::SSH.start for a description of each option.
    VALID_OPTIONS = [
      :auth_methods, :bind_address, :compression, :compression_level, :config,
      :encryption, :forward_agent, :hmac, :host_key,
      :keepalive, :keepalive_interval, :keepalive_maxcount, :kex, :keys, :key_data,
      :languages, :logger, :paranoid, :password, :port, :proxy,
      :rekey_blocks_limit,:rekey_limit, :rekey_packet_limit, :timeout, :verbose,
      :global_known_hosts_file, :user_known_hosts_file, :host_key_alias,
      :host_name, :user, :properties, :passphrase, :keys_only, :max_pkt_size,
      :max_win_size, :send_env, :use_agent, :number_of_password_prompts,
      :append_supported_algorithms, :non_interactive
    ]

    # The standard means of starting a new SSH connection. When used with a
    # block, the connection will be closed when the block terminates, otherwise
    # the connection will just be returned. The yielded (or returned) value
    # will be an instance of Net::SSH::Connection::Session (q.v.). (See also
    # Net::SSH::Connection::Channel and Net::SSH::Service::Forward.)
    #
    #   Net::SSH.start("host", "user") do |ssh|
    #     ssh.exec! "cp /some/file /another/location"
    #     hostname = ssh.exec!("hostname")
    #
    #     ssh.open_channel do |ch|
    #       ch.exec "sudo -p 'sudo password: ' ls" do |ch, success|
    #         abort "could not execute sudo ls" unless success
    #
    #         ch.on_data do |ch, data|
    #           print data
    #           if data =~ /sudo password: /
    #             ch.send_data("password\n")
    #           end
    #         end
    #       end
    #     end
    #
    #     ssh.loop
    #   end
    #
    # This method accepts the following options (all are optional):
    #
    # * auth_methods: an array of authentication methods to try
    # * bind_address: the IP address on the connecting machine to use in
    #   establishing connection. (:bind_address is discarded if :proxy
    #   is set.)
    # * compression: the compression algorithm to use, or +true+ to use
    #   whatever is supported.
    # * compression_level: the compression level to use when sending data
    # * config: set to +true+ to load the default OpenSSH config files
    #   (~/.ssh/config, /etc/ssh_config), or to +false+ to not load them, or to
    #   a file-name (or array of file-names) to load those specific configuration
    #   files. Defaults to +true+.
    # * encryption: the encryption cipher (or ciphers) to use
    # * forward_agent: set to true if you want the SSH agent connection to
    #   be forwarded
    # * global_known_hosts_file: the location of the global known hosts
    #   file. Set to an array if you want to specify multiple global known
    #   hosts files. Defaults to %w(/etc/ssh/ssh_known_hosts /etc/ssh/ssh_known_hosts2).
    # * hmac: the hmac algorithm (or algorithms) to use
    # * host_key: the host key algorithm (or algorithms) to use
    # * host_key_alias: the host name to use when looking up or adding a
    #   host to a known_hosts dictionary file
    # * host_name: the real host name or IP to log into. This is used
    #   instead of the +host+ parameter, and is primarily only useful when
    #   specified in an SSH configuration file. It lets you specify an
    #   "alias", similarly to adding an entry in /etc/hosts but without needing
    #   to modify /etc/hosts.
    # * keepalive: set to +true+ to send a keepalive packet to the SSH server
    #   when there's no traffic between the SSH server and Net::SSH client for
    #   the keepalive_interval seconds. Defaults to +false+.
    # * keepalive_interval: the interval seconds for keepalive.
    #   Defaults to +300+ seconds.
    # * keepalive_maxcount: the maximun number of keepalive packet miss allowed.
    # * kex: the key exchange algorithm (or algorithms) to use
    # * keys: an array of file names of private keys to use for publickey
    #   and hostbased authentication
    # * key_data: an array of strings, with each element of the array being
    #   a raw private key in PEM format.
    # * keys_only: set to +true+ to use only private keys from +keys+ and
    #   +key_data+ parameters, even if ssh-agent offers more identities. This
    #   option is intended for situations where ssh-agent offers many different
    #   identites.
    # * logger: the logger instance to use when logging
    # * max_pkt_size: maximum size we tell the other side that is supported per
    #   packet. Default is 0x8000 (32768 bytes). Increase to 0x10000 (65536 bytes)
    #   for better performance if your SSH server supports it (most do).
    # * max_win_size: maximum size we tell the other side that is supported for
    #   the window.
    # * paranoid: either false, true, :very, or :secure specifying how
    #   strict host-key verification should be (in increasing order here).
    #   You can also provide an own Object which responds to +verify+. The argument
    #   given to +verify+ is a hash consisting of the +:key+, the +:key_blob+,
    #   the +:fingerprint+ and the +:session+. Returning true accepts the host key,
    #   returning false declines it and closes the connection.
    # * passphrase: the passphrase to use when loading a private key (default
    #   is +nil+, for no passphrase)
    # * password: the password to use to login
    # * port: the port to use when connecting to the remote host
    # * properties: a hash of key/value pairs to add to the new connection's
    #   properties (see Net::SSH::Connection::Session#properties)
    # * proxy: a proxy instance (see Proxy) to use when connecting
    # * rekey_blocks_limit: the max number of blocks to process before rekeying
    # * rekey_limit: the max number of bytes to process before rekeying
    # * rekey_packet_limit: the max number of packets to process before rekeying
    # * send_env: an array of local environment variable names to export to the
    #   remote environment. Names may be given as String or Regexp.
    # * timeout: how long to wait for the initial connection to be made
    # * user: the user name to log in as; this overrides the +user+
    #   parameter, and is primarily only useful when provided via an SSH
    #   configuration file.
    # * user_known_hosts_file: the location of the user known hosts file.
    #   Set to an array to specify multiple user known hosts files.
    #   Defaults to %w(~/.ssh/known_hosts ~/.ssh/known_hosts2).
    # * use_agent: Set false to disable the use of ssh-agent. Defaults to 
    #   true
    # * non_interactive: set to true if your app is non interactive and prefers
    #   authentication failure vs password prompt
    # * verbose: how verbose to be (Logger verbosity constants, Logger::DEBUG
    #   is very verbose, Logger::FATAL is all but silent). Logger::FATAL is the
    #   default. The symbols :debug, :info, :warn, :error, and :fatal are also
    #   supported and are translated to the corresponding Logger constant.
    # * append_all_supported_algorithms: set to +true+ to append all supported
    #   algorithms by net-ssh. Was the default behaviour until 2.10
    # * number_of_password_prompts: Number of prompts for the password
    #   authentication method defaults to 3 set to 0 to disable prompt for
    #   password auth method
    # * non_interactive: non interactive applications should set it to true
    #   to prefer failing a password/etc auth methods vs asking for password
    def self.start(host, user, options={}, &block)
      invalid_options = options.keys - VALID_OPTIONS
      if invalid_options.any?
        raise ArgumentError, "invalid option(s): #{invalid_options.join(', ')}"
      end

      options[:user] = user if user
      options = configuration_for(host, options.fetch(:config, true)).merge(options)
      host = options.fetch(:host_name, host)

      if !options.key?(:logger)
        options[:logger] = Logger.new(STDERR)
        options[:logger].level = Logger::FATAL
      end

      if options[:non_interactive]
        options[:number_of_password_prompts] = 0
      end

      if options[:verbose]
        options[:logger].level = case options[:verbose]
          when Fixnum then options[:verbose]
          when :debug then Logger::DEBUG
          when :info  then Logger::INFO
          when :warn  then Logger::WARN
          when :error then Logger::ERROR
          when :fatal then Logger::FATAL
          else raise ArgumentError, "can't convert #{options[:verbose].inspect} to any of the Logger level constants"
        end
      end

      transport = Transport::Session.new(host, options)
      auth = Authentication::Session.new(transport, options)

      user = options.fetch(:user, user)
      if auth.authenticate("ssh-connection", user, options[:password])
        connection = Connection::Session.new(transport, options)
        if block_given?
          begin
            yield connection
          ensure
            connection.close unless connection.closed?
          end
        else
          return connection
        end
      else
        transport.close
        raise AuthenticationFailed, "Authentication failed for user #{user}@#{host}"
      end
    end

    # Returns a hash of the configuration options for the given host, as read
    # from the SSH configuration file(s). If +use_ssh_config+ is true (the
    # default), this will load configuration from both ~/.ssh/config and
    # /etc/ssh_config. If +use_ssh_config+ is nil or false, nothing will be
    # loaded (and an empty hash returned). Otherwise, +use_ssh_config+ may
    # be a file name (or array of file names) of SSH configuration file(s)
    # to read.
    #
    # See Net::SSH::Config for the full description of all supported options.
    def self.configuration_for(host, use_ssh_config=true)
      files = case use_ssh_config
        when true then Net::SSH::Config.default_files
        when false, nil then return {}
        else Array(use_ssh_config)
        end

      Net::SSH::Config.for(host, files)
    end
  end
end
