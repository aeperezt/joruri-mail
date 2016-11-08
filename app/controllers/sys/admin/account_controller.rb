class Sys::Admin::AccountController < Sys::Controller::Admin::Base
  protect_from_forgery except: [:login]
  layout 'base'

  def login
    admin_uri = '/webmail/INBOX/mails'

    #return redirect_to(admin_uri) if logged_in?
    if request.mobile? && params[:_session_id] == ''
      return redirect_to admin_uri
    end

    @uri = params[:uri] || cookies[:sys_login_referrer] || admin_uri
    @uri = @uri.gsub(/^http:\/\/[^\/]+/, '')
    @uri = NKF::nkf('-w', @uri)
    return unless request.post?

    if params[:password].to_s == 'p' + params[:account].to_s
      if Sys::User.where(account: params[:account]).first
        flash.now[:notice] = "初期パスワードではログインできません。<br />パスワードを変更してください。".html_safe
        respond_to do |format|
          format.html { render }
          format.xml  { render(:xml => '<errors />') }
        end
        return true
      end
    end

    if request.mobile? || request.smart_phone?
      login_ok = new_login_mobile(params[:account], params[:password], params[:mobile_password])
    else
      login_ok = new_login(params[:account], params[:password])
    end

    if login_ok
      Util::Syslog.info 'login succeeded', account: params[:account]
    else
      Util::Syslog.info 'login failed', account: params[:account]
      flash.now[:notice] = "ユーザーＩＤ・パスワードを正しく入力してください"
      respond_to do |format|
        format.html { render }
        format.xml  { render(:xml => '<errors />') }
      end
      return true
    end

    if params[:remember_me] == "1"
      user = Sys::User.find(self.current_user.id)
      user.remember_me
      cookies[:auth_token] = {
        :value   => user.remember_token,
        :expires => user.remember_token_expires_at
      }
    end

    cookies.delete :sys_login_referrer

    respond_to do |format|
      format.html { redirect_to @uri }
      format.xml  { render(:xml => current_user.to_xml) }
    end
  end

  def logout
    if logged_in?
      user = Sys::User.find(self.current_user.id)
      user.forget_me
    end
    cookies.delete :auth_token
    reset_session
    redirect_to action: :login
  end

  def info
    respond_to do |format|
      format.html { render }
      format.xml  { render :xml => Core.user.to_xml(:root => 'item', :include => :groups) }
    end
  end

  def sso
    config = load_sso_config
    raise 'SSOの設定がありません。' unless config

    @uri = URI::HTTP.build(
      scheme: config[:usessl] ? 'https' : 'http',
      host: config[:host],
      port: config[:port],
    )

    require 'net/http'
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = true if config[:usessl]
    http.start do |agent|
      response = agent.post(config[:path], {
        account: Core.user.account,
        password: Core.user.password,
        mobile_password: Core.user.mobile_password
      }.to_query)
      @token = response.body =~ /^OK/i ? response.body.gsub(/^OK /i, '') : nil
    end

    return redirect_to @uri.to_s unless @token

    @uri.path = config[:path]
    if request.get?
      @uri.query = Hash.new.tap { |h|
        h[:account] = Core.user.account
        h[:token] = @token
        h[:path] = params[:path] if params[:path].present?
      }.to_query
      return redirect_to @uri.to_s
    end
  end

  private

  def load_sso_config
    to = Joruri.config.sso_settings.keys.detect { |key| key == params[:to].to_sym } || :gw
    Joruri.config.sso_settings[to]
  end
end
