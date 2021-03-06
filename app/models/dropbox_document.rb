# Encoding: UTF-8
#	Written by: Zuinq Studio
#	Email: info@zuinqstudio.com 
#	Web: http://www.zuinqstudio.com 

# This work is licensed under a Creative Commons Attribution 3.0 License.
# [ http://creativecommons.org/licenses/by/3.0/ ]

# This means you may use it for any purpose, and make any changes you like.
# All we ask is that you include a link back to our page in your credits.

# Looking forward your comments and suggestions! clientes@signo-net.com

require 'rubygems'
require 'shoulda'
require 'pp'
require_dependency 'dropbox/lib/dropbox_sdk'


class DropboxException < RuntimeError
  def initialize
  end
end

class DropboxDocument < ActiveRecord::Base
  unloadable
  
  belongs_to :author, :class_name => "User", :foreign_key => "author_id"
  belongs_to :category, :class_name => "DocumentCategory", :foreign_key => "category_id"
  belongs_to :project

  acts_as_searchable :columns => ['title', "#{table_name}.title"], :include => :project

  validates_presence_of :project, :title, :category
  validates_length_of :title, :maximum => 60 

  attr_accessor :unsaved_attachments
  after_initialize :initialize_unsaved_attachments
  
  def before_save
  end
  
  def before_create
	logger.debug("****** Creando nuevo documento")
	self.created_on = Time.now
	self.updated_on = Time.now
	self.ruta = DropboxDocument.ruta_categoria_documento(self.project, self.category, self)
  end
  
  def before_update
	logger.debug("****** Actualizando documento")
	self.updated_on = Time.now
	#Miramos si ha cambiado la categoria o el nombre para mover la carpeta
	documento_guardado =  DropboxDocument.find(self.id)
	if self.category_id != documento_guardado.category_id || self.title != documento_guardado.title
		logger.debug("****** Hemos cambiado la categoria del archivo ")
		path_archivo = DropboxDocument.ruta_categoria_documento(self.project, self.category, self);
		logger.debug("****** Moviendo directorio de : " + self.ruta + " => " + path_archivo)
		conectado = dropbox_connect()
		if conectado
			movido_archivo = @client.file_move(self.ruta , path_archivo)
			if movido_archivo
				logger.debug("****** Movido directorio!!!")
				#Actualizamos la ruta del fichero
				self.ruta = path_archivo;
        
		        # Update attachments paths
		        self.attachments.each{|attachment|
		          attachment.update_path(self.ruta)
		        }
			end
		else
			raise DropboxException.new(), "No se ha podido mover el archivo de DropBox" + self.ruta
		end
	else
		logger.debug("****** No hemos cambiado la categoria del archivo ")
	end
  end
  
  def before_destroy
	logger.debug("****** Eliminando documentos de: " + self.title)
	#Ahora borramos la carpeta del archivo
	conectado = dropbox_connect()
	if conectado
		begin
			logger.debug("****** Eliminando directorio...")
			@client.file_delete(self.ruta)
			logger.debug("****** Eliminado directorio!!!")
			#Borramos los archivos
			attachments = self.attachments;
			attachments.each{|attachment|
				logger.debug("****** Eliminando documento de DropBox: " + attachment.ruta)
				#Ponemos la ruta vacía para evitar que borre uno a uno los archivos del dropbox. Hemos borrado antes la carpeta completa
				attachment.ruta = ""
				attachment.destroy
			}
		rescue DropboxError
			#raise DropboxException.new(), "No se ha podido eliminar el directorio de DropBox" + self.ruta
			#No hacemos nada porque es posible que la carpeta ya no existiera en Dropbox
		end
	end
  end
 
  def initialize_unsaved_attachments
    @unsaved_attachments ||= []
  end
  
  def attachments
	return DropboxAttachment.find(:all, :conditions => ["dropbox_document_id=" + self.id.to_s] , :order => "created_on DESC")
  end
  
  def dropbox_metadatos(path)
	conectado = dropbox_connect()
	error = false
	if conectado
		begin
			logger.debug("****** Recuperando metadatos de DropBox: " + path)
			metadatos = @client.metadata(path)
			if metadatos
				logger.debug("****** Recuperados metadatos")
				return metadatos
			else
				error = true
			end
		rescue DropboxError
			error = true
		end 
	else
		error = true
	end
	if error
		raise DropboxException.new(), "No se ha podido recuperar los metadatos del directorio: " + path 
	end
  end
  
  def dropbox_move(from, to)
	logger.debug("****** Renombreando fichero de '" + from + "' a '" + to + "'")
	conectado = dropbox_connect()
	error = false
	if conectado
		begin
			movido_archivo = @client.file_move(from , to)
			if movido_archivo
				logger.debug("****** Movido fichero!!!")
				#Actualizamos la ruta del fichero
				self.ruta = to;
			end
		rescue DropboxError
			error = true
		end
	else
		error = true
	end
	if error
		raise DropboxException.new(), "No se ha podido recuperar mover el archivo: " + from 
	end
  end
  
  def self.ruta_categoria(proyecto, category)
    return "/" + Setting.plugin_redmine_drop_box["PATH_BASE_DOCUMENTOS"] + "/" + DropboxAttachment.sanitize_filename(proyecto.identifier) + "/" + DropboxAttachment.sanitize_filename(category.name) + "/"
  end
  
  def self.ruta_categoria_documento(proyecto, category, documento)
    return ruta_categoria(proyecto, category) + DropboxAttachment.sanitize_filename(documento.title) + "/"
  end
   
  def self.check_repetido(document)
	repetido = DropboxDocument.find(:first, :conditions =>["ruta= ?", document.ruta])
	if repetido
		return true
	else
		return false
	end
  end

  private
 
  def dropbox_connect
	if @client
		logger.debug("****** Ya estaba conectando a DropBox... ")
		return true
	else
		logger.debug("****** Conectando a DropBox... ")

        # Check if user has no dropbox session...re-direct them to authorize
        return redirect_to(:action => 'authorize') unless Setting.plugin_redmine_drop_box[:dropbox_session]

		begin
	        @session = DropboxSession.deserialize(Setting.plugin_redmine_drop_box[:dropbox_session])
	        @client = DropboxClient.new(@session, ACCESS_TYPE) #raise an exception if session not authorized
	        @info = @client.account_info # look up account information
		rescue OAuth::Unauthorized
			raise DropboxException.new(), "No se ha podido conectar a DropBox. Usuario/password incorrecto/s"
		end
	end
  end
  
  
 end
